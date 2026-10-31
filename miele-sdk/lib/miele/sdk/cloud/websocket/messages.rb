# frozen_string_literal: true

module Miele
  module Sdk
    module Cloud
      class Websocket
        # The pushed messages, gathered from the frames as the app's WebsocketMessageParser does, each
        # acknowledged with its CloudConnectHeader.
        module Messages
          include Frames

          SEPARATOR = "\r\n\r\n"
          private_constant :SEPARATOR

          private

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

          # The app matches the header whatever its case, and a message without it breaks its stream.
          #
          # @param head [String, nil]
          # @return [Integer] its +Content-Length+
          # @raise [ConnectionError] without one
          def content_length(head)
            length = head.to_s[/Content-Length: (\d+)/i, 1] or raise ConnectionError, 'a message has no Content-Length'
            length.to_i
          end

          # @param text [String] the HTTP head, a blank line and the body
          # @return [Message] its path without trailing slashes, which the app trims before routing
          def message(text)
            head, body = text.split(SEPARATOR, 2)
            line, *fields = head.to_s.split("\r\n")
            headers = fields.to_h do |field|
              name, value = field.split(': ', 2)
              [name.to_s, value.to_s]
            end
            Message.new(path: line.to_s.split[1].to_s.sub(%r{/+\z}, ''), headers:, body: body.to_s)
          end
        end
      end
    end
  end
end
