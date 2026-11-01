# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # A bidi call that stays open, as the app holds its WebRTC and cloud archive streams: requests go out in the
      # order they are written, from any thread, while {#each} reads the responses. The call ends when the gateway
      # ends it, when a response is a failure, or at {#close}, which cancels it as the app does; it never half-closes.
      # Before the first response, an +UNAUTHENTICATED+ answer logs in again and replays every request written.
      class Exchange
        # grpc-ruby joins its writer thread once the gateway ends the call: a writer blocked on an empty queue would
        # hold the call open for good, so it checks the call's status between reads.
        POLL = 0.2
        private_constant :POLL

        # @param client [Client] the client whose {Client::Exchanges#converse} runs the call
        # @param path [String] a bidi gRPC path
        def initialize(client, path)
          @client = client
          @path = path
          @lock = Mutex.new
          @queue = Thread::Queue.new
          @written = [] #: Array[untyped]?
          @closed = false
        end

        # @param request [Hash, Data, Google::Protobuf::AbstractMessage] a request message
        # @return [self]
        # @raise [IOError] once the exchange is closed, by {#close} or at the end of its call
        def write(request)
          @lock.synchronize do
            raise IOError, 'the exchange is closed' if @closed

            @written&.push(request)
            @queue << request
          end
          self
        end

        # Runs the call on this thread until it ends.
        #
        # @yieldparam message [Data] each response message, or its success
        # @return [nil]
        # @raise [ReadError, CommandError] when a response is a failure
        def each(&block)
          @client.converse(@path, self) do |message|
            @lock.synchronize { @written = nil }
            block.call(message)
          end
        rescue GRPC::Cancelled
          raise unless @closed
        ensure
          close
        end

        # Cancels the call, from any thread.
        #
        # @return [nil]
        def close
          @lock.synchronize do
            @closed = true
            @queue.close
            @operation&.cancel
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
          queue = renew
          operation = nil #: untyped
          operation = yield(Enumerator.new { |out| drain(queue, -> { operation&.status }, out) })
          @lock.synchronize do
            @operation = operation
            return if @closed
          end
          operation.execute
          nil
        end

        private

        def renew
          @lock.synchronize do
            @queue.close
            @queue = Thread::Queue.new
            @written.to_a.each { @queue << it }
            @queue.close if @closed
            @queue
          end
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
            Exchange.new(self, path)
          end

          # Runs the call of an {Exchange}, logging in again before its first response as {Client#bidi} does.
          #
          # @api private
          # @param path [String] a bidi gRPC path
          # @param exchange [Exchange]
          # @yieldparam message [Data] each response message, or its success
          # @return [nil]
          def converse(path, exchange, &block)
            fresh = true
            relay = lambda do |bytes|
              fresh = false
              block.call(settle(path, value(path, bytes)))
            end
            authenticating(-> { fresh }) do |metadata|
              exchange.run { |requests| operation(path, requests, metadata, relay) }
            end
          end

          private

          def operation(path, requests, metadata, relay)
            stub.bidi_streamer(path, requests.lazy.map { message(path, it) }, encoder(path), IDENTITY,
                               metadata:, return_op: true, &relay)
          end
        end
      end
    end
  end
end
