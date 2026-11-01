# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # A bidi call that stays open, as the app holds its WebRTC and cloud archive streams: requests go out in the
      # order they are written, from any thread, while {#each} reads the responses. The call ends when the gateway
      # ends it, when a response is a failure, or at {#close}, which cancels it as the app does; it never half-closes.
      class Exchange
        # grpc-ruby joins its writer thread once the gateway ends the call: a writer blocked on an empty queue would
        # hold the call open for good, so it checks the call's status between reads.
        POLL = 0.2
        private_constant :POLL

        # @param client [Client] the client whose {Client::Exchanges#converse} runs the call
        # @param path [String] a bidi gRPC path
        # @yieldparam request [Hash, Data, Google::Protobuf::AbstractMessage] a request written
        # @yieldreturn [Google::Protobuf::AbstractMessage] the message it sends
        def initialize(client, path, &message)
          @client = client
          @path = path
          @message = message
          @lock = Mutex.new
          @queue = Thread::Queue.new
          @started = false
          @closed = false
        end

        # @param request [Hash, Data, Google::Protobuf::AbstractMessage] a request message
        # @return [self]
        # @raise [ArgumentError, TypeError] for a request the path does not take, which nothing sends
        # @raise [IOError] once the exchange is closed, by {#close} or when {#each} returns
        def write(request)
          message = @message.call(request)
          @lock.synchronize do
            raise IOError, 'the exchange is closed' if @closed

            @queue << message
          end
          self
        end

        # Runs the call on this thread until it ends; an exchange runs once.
        #
        # @yieldparam message [Data] each response message, or its success
        # @return [nil, Enumerator] an Enumerator of the messages when no block is given; leaving it closes the call
        # @raise [ReadError, CommandError] when a response is a failure
        # @raise [IOError] when the exchange is closed or has run
        def each(&block)
          return enum_for(:each) unless block

          @lock.synchronize do
            raise IOError, 'the exchange is closed or has run' if @closed || @started

            @started = true
          end
          relay(&block)
        end

        # Cancels the call, from any thread.
        #
        # @return [nil]
        def close
          @lock.synchronize do
            @closed = true
            @operation&.cancel
            @queue.close
          end
          nil
        end

        # Opens one call through the block, which turns the requests into a gRPC operation, and runs it.
        #
        # @api private
        # @yieldparam requests [Enumerator] the requests of this call, read while it lasts
        # @yieldreturn [GRPC::ActiveCall::Operation]
        # @return [nil]
        def run
          operation = nil #: untyped
          operation = yield(Enumerator.new { |out| drain(@queue, -> { operation&.status }, out) })
          @lock.synchronize do
            @operation = operation
            return if @closed
          end
          operation.execute
          nil
        end

        private

        def relay(&)
          @client.converse(@path, self, &)
        rescue GRPC::Cancelled
          raise unless @closed
        ensure
          close
        end

        def drain(queue, ended, out)
          until ended.call
            request = queue.pop(timeout: POLL)
            break if request.nil? && queue.closed?

            out << request unless request.nil?
          end
        end
      end

      class Client
        # Opens {Exchange}s, mixed into {Client}.
        module Exchanges
          # @param path [String] a bidi gRPC path
          # @return [Exchange] the call, which starts at {Exchange#each}
          # @raise [ReadOnlyError] for a path that writes, under read-only
          def exchange(path)
            refuse_write(path)
            Exchange.new(self, path) { message(path, it) }
          end

          # Runs the call of an {Exchange}.
          #
          # @api private
          # @param path [String] a bidi gRPC path
          # @param exchange [Exchange]
          # @yieldparam message [Data] each response message, or its success
          # @return [nil]
          def converse(path, exchange, &block)
            relay = ->(bytes) { block.call(settle(path, value(path, bytes))) }
            authenticating do |metadata|
              exchange.run { |requests| operation(path, requests, metadata, relay) }
            end
          end

          private

          def operation(path, requests, metadata, relay)
            stub.bidi_streamer(path, requests, encoder(path), IDENTITY, metadata:, return_op: true, &relay)
          end
        end
      end
    end
  end
end
