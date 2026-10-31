# frozen_string_literal: true

require 'io/wait'
require 'uri'

module Miele
  module Sdk
    module Cloud
      # The Miele cloud websocket as the app's Websocket.Client speaks it: every resource the account pushes,
      # each acknowledged, the connection kept alive with an unsolicited pong every 30 s, as .NET does with a
      # KeepAliveInterval alone.
      class Websocket
        include Handshake
        include Frames

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
        SEPARATOR = "\r\n\r\n"
        private_constant :KEEP_ALIVE, :SEPARATOR

        # @param session [Session]
        # @param url [String] the cloud's websocket, +wss://{rest host}/websocket/V2/Devices/+ by default
        # @param clock [#call] seconds, monotonic
        def initialize(session, url: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @session = session
          @url = URI(url || "#{session.organization.rest.sub(/\Ahttp/, 'ws')}/websocket/V2/Devices/")
          @clock = clock
        end

        # @yieldparam message [Message]
        # @return [void]
        # @raise [ConnectionError] when the cloud refuses the connection
        # @raise [EOFError] when it closes it
        # @api public
        def each(&)
          socket = connect
          listen(socket, &)
        ensure
          close(socket) if socket
        end

        private

        # @param socket [IO]
        # @yieldparam message [Message]
        # @return [void]
        def listen(socket, &)
          buffer = ''.b
          due = @clock.call + KEEP_ALIVE
          loop do
            due = alive(socket, due)
            opcode, payload = read_frame(socket)
            return if opcode == CLOSE

            buffer = receive(socket, opcode, payload, buffer, &)
          end
        end

        # The app acknowledges each message it parses.
        #
        # @param socket [IO]
        # @param opcode [Integer]
        # @param payload [String]
        # @param buffer [String] what is left of the previous frames
        # @yieldparam message [Message]
        # @return [String] what is left now
        def receive(socket, opcode, payload, buffer)
          write_frame(socket, PONG, payload) if opcode == PING
          return buffer unless [CONTINUATION, TEXT, BINARY].include?(opcode)

          parse(buffer + payload) do |header, message|
            write_frame(socket, TEXT, "#{header}#{SEPARATOR}HTTP/1.1 204 No Content#{SEPARATOR}")
            yield message
          end
        end

        # @param socket [IO]
        # @param due [Float] when the next keep-alive is due
        # @return [Float] the next one once a frame is ready
        def alive(socket, due)
          until readable?(socket, due - @clock.call)
            write_frame(socket, PONG, '')
            due += KEEP_ALIVE
          end
          due
        end

        # @param socket [IO]
        # @param timeout [Float]
        # @return [Boolean]
        def readable?(socket, timeout)
          return true if socket.respond_to?(:pending) && socket.pending.positive?

          !socket.to_io.wait_readable([timeout, 0].max).nil?
        end

        # @param buffer [String]
        # @yieldparam header [String] the CloudConnectHeader
        # @yieldparam message [Message]
        # @return [String] what is left
        def parse(buffer)
          loop do
            header, text, rest = split(buffer)
            return buffer unless header && text && rest

            yield header, message(text)
            buffer = rest
          end
        end

        # WebsocketMessageParser: the CloudConnectHeader, the HTTP head, then +Content-Length+ bytes of body; a
        # partial message waits in the buffer.
        #
        # @param buffer [String]
        # @return [Array(String, String, String), nil] the header, the HTTP message and what follows
        def split(buffer)
          cloud_end = buffer.index(SEPARATOR)
          head_end = cloud_end && buffer.index(SEPARATOR, cloud_end + 4)
          return unless cloud_end && head_end

          ending = head_end + 4 + content_length(buffer[cloud_end...head_end])
          return if buffer.bytesize < ending

          [buffer[0...cloud_end].to_s, buffer[(cloud_end + 4)...ending].to_s, buffer[ending..].to_s]
        end

        # @param head [String, nil]
        # @return [Integer] its +Content-Length+, 0 without one
        def content_length(head) = head.to_s[/Content-Length: (\d+)/, 1].to_i

        # @param text [String] the HTTP head, a blank line and the body
        # @return [Message]
        def message(text)
          head, body = text.split(SEPARATOR, 2)
          line, *fields = head.to_s.split("\r\n")
          headers = fields.to_h do |field|
            name, value = field.split(': ', 2)
            [name.to_s, value.to_s]
          end
          Message.new(path: line.to_s.split[1].to_s, headers:, body: body.to_s)
        end

        # @param socket [IO]
        # @return [void]
        def close(socket)
          write_frame(socket, CLOSE, '')
        rescue IOError, SystemCallError
          nil
        ensure
          socket.close
        end
      end
    end
  end
end
