# frozen_string_literal: true

require 'io/wait'
require 'uri'

module Miele
  module Sdk
    module Cloud
      # The Miele cloud websocket as the app's Websocket.Client speaks it: every resource the account pushes,
      # each acknowledged, the connection kept alive with an unsolicited pong every 30 s, as .NET does with a
      # KeepAliveInterval alone. It reconnects as the app does: 6 s after an error, 3 s after a message it cannot
      # parse, at once after a minute without a message.
      class Websocket
        include Handshake
        include Frames
        include Messages

        # A pushed resource.
        #
        # @!attribute [r] path
        #   @return [String] such as +/V2/Devices/000123456789/State+
        # @!attribute [r] headers
        #   @return [Hash{String=>String}]
        # @!attribute [r] body
        #   @return [String] JSON, or a DOP2 leaf
        Message = Data.define(:path, :headers, :body)

        KEEP_ALIVE = 30
        WATCHDOG = 60
        ERROR_RECONNECT = 6
        # The app's message stream starts again 3 s after a message it cannot parse (RetryWhen), and its library
        # reconnects 6 s after any other error (ErrorReconnectTimeout).
        STREAM_RETRY = 3
        FAILURES = [ConnectionError, ResponseError, SocketError, EOFError, IOError, SystemCallError,
                    OpenSSL::SSL::SSLError].freeze
        private_constant :KEEP_ALIVE, :WATCHDOG, :ERROR_RECONNECT, :STREAM_RETRY, :FAILURES

        # @param session [Session] its organization's rest host names the websocket,
        #   +wss://{host}/websocket/V2/Devices/+
        # @param follow [#call] the resources to read again, called on each connection: +/Devices/{fab}/State+…
        # @param fetch [#call] reads one of them, the cloud channel by default
        # @param clock [#call] seconds, monotonic
        # @param sleeper [#call] waits the given number of seconds
        def initialize(session, follow: -> { [] }, fetch: nil,
                       clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: method(:sleep))
          @session = session
          @url = URI("#{session.organization.rest.sub(/\Ahttp/, 'ws')}/websocket/V2/Devices/")
          @follow = follow
          @fetch = fetch || ->(path) { Channel.new(session).request(:get, path).body }
          @clock = clock
          @sleeper = sleeper
        end

        # Reconnects until the block breaks, which closes the connection, or raises, which ends it with that error.
        #
        # @yieldparam message [Message] a pushed resource, or one read again on connecting
        # @return [void]
        # @api public
        def each(&)
          error = catch do |tag|
            loop do
              wait = connection { |message| hand_over(message, tag, &) }
              @sleeper.call(wait) if wait.positive?
            end
          end
          raise error
        end

        private

        # Carries what the block raises past the rescue that reconnects.
        #
        # @param message [Message]
        # @param tag [Object] the +catch+ of {#each}
        # @yieldparam message [Message]
        # @return [void]
        def hand_over(message, tag)
          yield message
        rescue StandardError => e
          throw tag, e
        end

        # @yieldparam message [Message]
        # @return [Integer] the seconds to wait before connecting again
        def connection(&)
          @input = ''.b
          socket = connect
          refetch(&)
          listen(socket, &) == :silent ? 0 : ERROR_RECONNECT
        rescue *FAILURES => e
          wait_after(e)
        ensure
          close(socket) if socket
        end

        # @param error [Exception] what ended the connection
        # @return [Integer] the seconds to wait: none when a frame outlived the watchdog, as when no message came
        def wait_after(error)
          case error
          when Malformed then STREAM_RETRY
          when IO::TimeoutError then 0
          else ERROR_RECONNECT
          end
        end

        # SendFreshRequest and SendFreshRequestUponReconnect: the app reads each followed resource on every
        # connection; one that fails is left out.
        #
        # @yieldparam message [Message]
        # @return [void]
        def refetch
          @follow.call.each do |path|
            body = @fetch.call(path)
          rescue Error
            next
          else
            yield Message.new(path: "/V2#{path}", headers: {}, body:)
          end
        end

        # @param socket [IO]
        # @yieldparam message [Message]
        # @return [Symbol, nil] +:silent+ when no message came for a minute, nil when the cloud closes
        def listen(socket, &)
          buffer = ''.b
          keep_alive, silence = deadlines
          loop do
            keep_alive = wait(socket, keep_alive, silence)
            return :silent unless keep_alive

            opcode, payload = read_frame(socket, [silence - @clock.call, 0].max)
            return if opcode == CLOSE

            silence = @clock.call + WATCHDOG if [CONTINUATION, TEXT, BINARY].include?(opcode)
            buffer = receive(socket, opcode, payload, buffer, &)
          end
        end

        # @param now [Float]
        # @return [Array(Float, Float)] when the next keep-alive is due and when the watchdog gives up
        def deadlines(now = @clock.call) = [now + KEEP_ALIVE, now + WATCHDOG]

        # @param socket [IO]
        # @param keep_alive [Float] when the next keep-alive is due
        # @param silence [Float] when the watchdog gives up
        # @return [Float, nil] the next keep-alive once a frame is ready, nil once the watchdog gives up
        def wait(socket, keep_alive, silence)
          loop do
            now = @clock.call
            return if now >= silence
            return keep_alive if readable?(socket, [keep_alive, silence].min - now)
            next if @clock.call < keep_alive

            write_frame(socket, PONG, '')
            keep_alive += KEEP_ALIVE
          end
        end

        # OpenSSL::Buffering keeps what it reads past a frame where neither +pending+ nor the socket shows it: a
        # read that does not block takes it first.
        #
        # @param socket [IO]
        # @param timeout [Float]
        # @return [Boolean]
        def readable?(socket, timeout)
          return true unless @input.empty?

          chunk = socket.read_nonblock(CHUNK, exception: false)
          return !socket.to_io.wait_readable([timeout, 0].max).nil? if chunk.is_a?(Symbol)

          @input << chunk.to_s # nil once the cloud closes, which the next read raises
          true
        end

        # @param socket [IO]
        # @return [void]
        def close(socket)
          write_frame(socket, CLOSE, '')
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
          nil
        ensure
          socket.close
        end
      end
    end
  end
end
