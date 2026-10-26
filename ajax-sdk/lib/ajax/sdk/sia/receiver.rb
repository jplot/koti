# frozen_string_literal: true

require 'socket'

module Ajax
  module Sdk
    module Sia
      # A TCP server standing as the hub's monitoring station. It answers each frame (ACK, NAK or DUH) and
      # hands each accepted event to the block, after the ACK. Each hub connection runs in its own thread,
      # so the block may be called from several threads at once.
      class Receiver
        # The 0LLL length field caps a frame at 4105 bytes; a peer that never sends +\r+ stays bounded.
        LIMIT = 4105
        private_constant :LIMIT

        # @param host [String] the address to bind
        # @param port [Integer] the port to bind; 0 picks a free one (see {#port})
        # @param account [String] the account (object number) set on the hub
        # @param key [String, nil] the encryption key set on the hub; without one, only clear frames pass
        # @param timeband [Array(Integer, Integer)] seconds a timestamp may lag behind or run ahead
        # @yieldparam event [Event]
        def initialize(host:, port:, account:, key:, timeband:, &handler)
          @host = host
          @port = port
          @account = account
          @cipher = key && Cipher.new(key)
          @timeband = timeband
          @handler = handler
          @clients = {}
          @mutex = Mutex.new
        end

        # @return [self]
        def start
          @server = TCPServer.new(@host, @port)
          @acceptor = Thread.new { accept_loop }
          self
        end

        # @return [Integer] the port the receiver listens on
        def port = @server.local_address.ip_port

        # Closes the listening socket and every hub connection, then waits for their threads.
        #
        # @return [void]
        def stop
          @server.close
          @acceptor.join
          @mutex.synchronize { @clients.dup }.each do |socket, thread|
            socket.close
            thread.join
          end
        end

        private

        def accept_loop
          loop do
            socket = @server.accept
            @mutex.synchronize { @clients[socket] = Thread.new { serve(socket) } }
          end
        rescue IOError, SystemCallError
          nil
        end

        def serve(socket)
          while (frame = socket.gets("\r", LIMIT))
            reply, event = answer(frame)
            socket.write(reply) if reply
            @handler.call(event) if event
          end
        rescue IOError, SystemCallError
          nil
        ensure
          socket.close
          @mutex.synchronize { @clients.delete(socket) }
        end

        def answer(frame)
          message = Message.parse(frame)
          return [message.duh, nil] unless message.account == @account && message.encrypted == !@cipher.nil?

          message = Message.parse(frame, cipher: @cipher) if message.encrypted
          return [Message.nak, nil] unless timely?(message.timestamp)

          [message.ack(cipher: @cipher), message.type == 'NULL' ? nil : Event.from(message)]
        rescue FrameError
          [nil, nil]
        end

        def timely?(time)
          now = Time.now
          time.nil? || ((now - @timeband[0])..(now + @timeband[1])).cover?(time)
        end
      end
    end
  end
end
