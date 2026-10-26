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
      # +UNAUTHENTICATED+ answer, logs in again and retries the call once.
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
        # @return [Hash, nil] the response Hash, or nil for a streaming call read through its block
        def call(path, request = {}, &)
          public_send(Schemas.rpc(path).type, path, request, &)
        end

        # @return [Hash] the single response message
        def unary(path, request = {})
          refuse_write(path)
          authenticating { |md| invoke(:request_response, path, message(path, request), md) }
        end

        # @yieldparam message [Hash] each response message
        # @return [void]
        def server_stream(path, request = {}, &)
          authenticating { |md| invoke(:server_streamer, path, message(path, request), md, &) }
        end

        # @param requests [Array<Hash>] the request messages
        # @return [Hash] the single response message
        def client_stream(path, requests)
          refuse_write(path)
          authenticating { |md| invoke(:client_streamer, path, requests.map { |request| message(path, request) }, md) }
        end

        # @yieldparam message [Hash] each response message
        # @return [void]
        def bidi(path, requests, &)
          refuse_write(path)
          messages = requests.map { |request| message(path, request) }
          authenticating { |md| invoke(:bidi_streamer, path, messages, md, &) }
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
            @stub ||= GRPC::ClientStub.new("#{@settings.grpc_host}:#{@settings.grpc_port}", credentials,
                                           timeout: @settings.read_timeout)
          end
        end

        def credentials
          ca = @settings.ca_file
          GRPC::Core::ChannelCredentials.new(ca && File.read(ca))
        end

        def invoke(kind, path, request, metadata, &block)
          marshal = Schemas.message(Schemas.rpc(path).request).method(:encode)
          decode = Schemas.message(Schemas.rpc(path).response).method(:decode)
          relay = block && ->(bytes) { block.call(decode.call(bytes).to_h) }
          result = stub.public_send(kind, path, request, marshal, IDENTITY, metadata:, &relay)
          relay ? nil : decode.call(result).to_h
        end

        def message(path, request)
          klass = Schemas.message(Schemas.rpc(path).request)
          request.is_a?(klass) ? request : klass.new(request)
        end

        def refuse_write(path)
          return unless read_only? && READS.none? { |method| path.end_with?("/#{method}") }

          raise ReadOnlyError, "#{path} refused: the client is read-only"
        end

        def authenticating
          @session.ensure_login
          yield(@session.metadata)
        rescue GRPC::Unauthenticated
          @session.login
          yield(@session.metadata)
        end
      end
    end
  end
end
