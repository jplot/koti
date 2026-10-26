# frozen_string_literal: true

require 'grpc'
require_relative 'schemas'
require_relative 'session'
require_relative 'resources'

module Ajax
  module Sdk
    module Cloud
      # Talks to the Ajax mobile gateway over gRPC. It resolves a path to its request and response
      # messages through {Schemas}, sends the call of the right kind, and attaches the app and session
      # metadata the gateway expects. One {Session} rides along: the client logs in lazily and, on an
      # +UNAUTHENTICATED+ answer, logs in again and retries the call once (a stream, only before its
      # first message).
      #
      # Responses come back as plain Hashes: google-protobuf's field readers misbehave on messages
      # decoded against a private descriptor pool, but +to_h+ is reliable, so every response is turned
      # into a Hash right after decoding.
      class Client
        include Resources

        IDENTITY = ->(bytes) { bytes }
        # Unary methods that only read; under read-only, every other unary, client-stream or bidi call
        # is refused. Server streams are reads, so they are always allowed.
        READS = %w[findUserSpacesWithPagination findNotifications].freeze
        private_constant :IDENTITY, :READS

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

        # Sends +request+ (a Hash) on +path+, choosing the call kind from the method table.
        #
        # @param path [String] a gRPC path, +/<service>/<method>+
        # @param request [Hash] the request message as a Hash
        # @return [Hash, Enumerator, nil] the response Hash; for a stream, an Enumerator, or nil when
        #   read through the block
        def call(path, request = {}, &)
          public_send(Schemas.rpc(path).type, path, request, &)
        end

        # @return [Hash] the single response message
        def unary(path, request = {})
          refuse_write(path)
          authenticating { |md| invoke(:request_response, path, message(path, request), md) }
        end

        # Leaving the stream before its end, through +break+ or an Enumerator's +first+, cancels the call.
        #
        # @yieldparam message [Hash] each response message
        # @return [Enumerator, nil] an Enumerator of the messages when no block is given
        def server_stream(path, request = {}, &)
          return enum_for(:server_stream, path, request) unless block_given?

          stream(:server_streamer, path, message(path, request), &)
        end

        # @param requests [Array<Hash>] the request messages
        # @return [Hash] the single response message
        def client_stream(path, requests)
          refuse_write(path)
          authenticating { |md| invoke(:client_streamer, path, requests.map { |request| message(path, request) }, md) }
        end

        # @yieldparam message [Hash] each response message
        # @return [Enumerator, nil] an Enumerator of the messages when no block is given
        def bidi(path, requests, &)
          refuse_write(path)
          return enum_for(:bidi, path, requests) unless block_given?

          stream(:bidi_streamer, path, requests.map { |request| message(path, request) }, &)
        end

        # Sends a unary call without the login retry, so {Session} can log in without recursing.
        #
        # @api private
        # @return [Hash] the response message
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
          decode(path, stub.public_send(kind, path, request, encoder(path), IDENTITY, metadata:, deadline:))
        end

        # Logs in again only before the first message: a retry after it would replay what was yielded.
        def stream(kind, path, request, &block)
          fresh = true
          relay = lambda do |bytes|
            fresh = false
            block.call(decode(path, bytes))
          end
          authenticating(-> { fresh }) do |metadata|
            stub.public_send(kind, path, request, encoder(path), IDENTITY, metadata:, &relay)
            nil
          end
        end

        def encoder(path) = Schemas.message(Schemas.rpc(path).request).method(:encode)

        def decode(path, bytes) = Schemas.message(Schemas.rpc(path).response).decode(bytes).to_h

        def message(path, request)
          klass = Schemas.message(Schemas.rpc(path).request)
          request.is_a?(klass) ? request : klass.new(request)
        end

        def refuse_write(path)
          return unless read_only? && READS.none? { |method| path.end_with?("/#{method}") }

          raise ReadOnlyError, "#{path} refused: the client is read-only"
        end

        def authenticating(retriable = -> { true })
          @session.ensure_login
          yield(@session.metadata)
        rescue GRPC::Unauthenticated
          raise unless retriable.call

          @session.login
          yield(@session.metadata)
        end
      end
    end
  end
end
