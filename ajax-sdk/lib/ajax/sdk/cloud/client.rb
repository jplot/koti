# frozen_string_literal: true

require 'grpc'
require_relative 'schemas'
require_relative 'values'
require_relative 'session'
require_relative 'resources'
require_relative 'methods'
require_relative 'shortcuts'
require_relative 'feed'

module Ajax
  module Sdk
    module Cloud
      # Talks to the Ajax mobile gateway over gRPC. It resolves a path to its request and response
      # messages through {Schemas}, sends the call of the right kind, and attaches the app and session
      # metadata the gateway expects. One {Session} rides along: the client logs in lazily and, on an
      # +UNAUTHENTICATED+ answer, logs in again and retries the call once (a stream, only before its
      # first message).
      #
      # Responses come back as the typed values of {Messages}, built from +to_h+: google-protobuf's field
      # readers misbehave on messages decoded against a private descriptor pool, but +to_h+ is reliable. A
      # response whose +success+ shares a oneof with its +failure+ gives its success, or raises {ReadError} or
      # {CommandError} with the failure.
      class Client
        include Resources
        include Methods
        include Shortcuts

        IDENTITY = ->(bytes) { bytes }
        # Under read-only, a method runs only when its name starts with a read word and holds no write one, streams
        # included: stream_create_access_card writes. The doubtful ones of the app 3.59 (tests, scans) are refused.
        READ_WORDS = %w[get find search stream].freeze
        WRITE_WORDS = %w[create delete reset registration exclusion test calibration survey scan transfer].freeze
        private_constant :IDENTITY, :READ_WORDS, :WRITE_WORDS

        # @param settings [Configuration::Settings] the account and endpoint settings
        def initialize(settings = Ajax::Sdk.config)
          @settings = settings
          @session = Session.new(self, settings)
          @mutex = Mutex.new
        end

        # @return [Session] the login session
        attr_reader :session

        # @return [String] a description that never prints the account's secrets
        def inspect = "#<#{self.class.name} gateway=#{@settings.grpc_host}>"

        # Sends +request+ on +path+, choosing the call kind from the method table.
        #
        # @param path [String] a gRPC path, +/<service>/<method>+
        # @param request [Hash, Data, Google::Protobuf::AbstractMessage] the request message as a Hash, a
        #   generated value or a google-protobuf message
        # @return [Data, Enumerator, nil] the response, or its success; for a stream, an Enumerator, or nil
        #   when read through the block
        # @raise [ReadError, CommandError] when the gateway answers a failure: a read raises {ReadError}
        def call(path, request = {}, &)
          public_send(Schemas.rpc(path).type, path, request, &)
        end

        # @return [Data] the single response message, or its success
        def unary(path, request = {})
          refuse_write(path)
          request = message(path, request)
          authenticating { |md| settle(path, invoke(:request_response, path, request, md)) }
        end

        # Leaving the stream before its end, through +break+ or an Enumerator's +first+, cancels the call.
        #
        # @yieldparam message [Data] each response message, or its success
        # @return [Enumerator, nil] an Enumerator of the messages when no block is given
        def server_stream(path, request = {}, &)
          refuse_write(path)
          request = message(path, request)
          return enum_for(:server_stream, path, request) unless block_given?

          stream(:server_streamer, path, request, &)
        end

        # @param requests [Array<Hash, Data>] the request messages
        # @return [Data] the single response message, or its success
        def client_stream(path, requests)
          refuse_write(path)
          requests = requests.map { message(path, it) }
          authenticating { |md| settle(path, invoke(:client_streamer, path, requests, md)) }
        end

        # @yieldparam message [Data] each response message, or its success
        # @return [Enumerator, nil] an Enumerator of the messages when no block is given
        def bidi(path, requests, &)
          refuse_write(path)
          requests = requests.map { message(path, it) }
          return enum_for(:bidi, path, requests) unless block_given?

          stream(:bidi_streamer, path, requests, &)
        end

        # Sends a unary call without the login retry, so {Session} can log in without recursing.
        #
        # @api private
        # @return [Data] the response message, whole
        def authenticate(path, request, metadata)
          invoke(:request_response, path, message(path, request), metadata)
        end

        # @return [Hash{String=>String}] the current call metadata
        def metadata = @session.metadata

        # @return [Boolean] whether state-changing commands are refused
        def read_only? = @settings.read_only

        private

        def stub
          @mutex.synchronize do
            @stub ||= GRPC::ClientStub.new("#{@settings.grpc_host}:#{@settings.grpc_port}", credentials)
          end
        end

        def credentials
          ca = @settings.ca_file
          GRPC::Core::ChannelCredentials.new(ca && File.read(ca))
        end

        def invoke(kind, path, request, metadata)
          deadline = Time.now + @settings.read_timeout
          value(path, stub.public_send(kind, path, request, encoder(path), IDENTITY, metadata:, deadline:))
        end

        # Logs in again only before the first message: a retry after it would replay what was yielded.
        def stream(kind, path, request, &block)
          fresh = true
          relay = lambda do |bytes|
            fresh = false
            block.call(settle(path, value(path, bytes)))
          end
          authenticating(-> { fresh }) do |metadata|
            stub.public_send(kind, path, request, encoder(path), IDENTITY, metadata:, &relay)
            nil
          end
        end

        def encoder(path) = Schemas.message(Schemas.rpc(path).request).method(:encode)

        def value(path, bytes)
          response = Schemas.rpc(path).response
          Messages.type(response).from(Schemas.message(response).decode(bytes).to_h)
        end

        def message(path, request)
          klass = Schemas.message(Schemas.rpc(path).request)
          return request if request.is_a?(klass)

          klass.new(request.respond_to?(:to_message) ? request.to_message : request)
        end

        def settle(path, value) = Outcome.settle(value, read?(path) ? ReadError : CommandError)

        def refuse_write(path)
          return if !read_only? || read?(path)

          raise ReadOnlyError, "#{path} refused: the client is read-only"
        end

        def read?(path)
          service, method = path.delete_prefix('/').split('/')
          name = method == 'execute' ? service.to_s.split('.').last.to_s.delete_suffix('Service') : method.to_s
          words = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.split('_')
          READ_WORDS.include?(words.first) && !words.intersect?(WRITE_WORDS)
        end

        def authenticating(retriable = -> { true })
          @session.ensure_login
          metadata = @session.metadata
          yield(metadata)
        rescue GRPC::Unauthenticated
          raise unless retriable.call

          @session.login(metadata&.fetch('client-session-token', nil))
          yield(@session.metadata)
        end
      end
    end
  end
end
