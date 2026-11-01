# frozen_string_literal: true

require 'socket'

module Ajax
  module Sdk
    module Sia
      # A TCP server standing as the hub's monitoring station. It answers each frame (ACK, NAK or DUH) and
      # hands each accepted event to the block, after the ACK. Each hub connection runs in its own thread,
      # so the block may be called from several threads at once; an exception it raises ends that
      # connection's thread, which Ruby reports as it does for any thread, and the connection with it. One
      # address keeps at most 8 connections open: a ninth closes the oldest.
      class Receiver
        # The 0LLL length field caps a frame at 4105 bytes; a peer that never sends +\r+ stays bounded.
        LIMIT = 4105
        # A hub that reconnects after a network drop can leave its old connection half-open for good.
        PER_PEER = 8
        # EMFILE lasts until a connection closes; accepting again at once would spin.
        BACKOFF = 0.1
        private_constant :LIMIT, :PER_PEER, :BACKOFF

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
          clients = @mutex.synchronize { @clients.dup }
          clients.each_key(&:close)
          clients.each_value { |(_, thread)| finish(thread) }
        end

        private

        # A block's exception ends its connection's thread, which Ruby reports; stop must still wait for the others.
        def finish(thread)
          thread.join
        rescue StandardError
          nil
        end

        def accept_loop
          until @server.closed?
            begin
              admit(@server.accept)
            rescue IOError, SystemCallError
              sleep(BACKOFF) unless @server.closed?
            end
          end
        end

        # Past PER_PEER connections from one address, its oldest is closed.
        def admit(socket)
          peer = socket.remote_address.ip_address
          @mutex.synchronize do
            @clients.select { |_, (address, _)| address == peer }.keys.reverse.drop(PER_PEER - 1).each(&:close)
            @clients[socket] = [peer, Thread.new { serve(socket) }]
          end
        rescue SystemCallError, ThreadError
          socket.close
        end

        def serve(socket)
          while (event = receive(socket))
            @handler.call(event)
          end
        ensure
          socket.close
          @mutex.synchronize { @clients.delete(socket) }
        end

        def receive(socket)
          while (frame = socket.gets("\r", LIMIT))
            reply, event = answer(frame)
            socket.write(reply) if reply
            return event if event
          end
        rescue IOError, SystemCallError
          nil
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
