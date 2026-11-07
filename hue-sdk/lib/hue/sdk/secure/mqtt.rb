# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The few MQTT 3.1.1 packets {Follow} sends and reads.
      module Mqtt
        module_function

        # @param type [Integer] the first byte
        # @param body [String]
        # @return [String] the packet, its remaining length in 7-bit groups
        # @api private
        def packet(type, body)
          length = body.bytesize
          bytes = [] #: Array[Integer]
          loop do
            bytes << ((length & 0x7f) | (length > 0x7f ? 0x80 : 0))
            length >>= 7
            break if length.zero?
          end
          [type, *bytes].pack('C*') + body
        end

        # @param text [String]
        # @return [String] its length on two bytes, then its bytes
        # @api private
        def string(text) = [text.bytesize].pack('n') + text.b

        # A TLS connection to the broker. Its packets come from a buffer of its own: OpenSSL keeps the bytes of a record
        # it has read where a wait on the socket does not see them. It pings once +keep_alive+ seconds have passed since
        # it last sent, as the app's keep-alive does, and gives up when a ping gets no answer in as long.
        class Link
          # Opens TLS with ALPN +mqtt+, trusting the pinned root alone, its handshake bounded by +open_timeout+.
          #
          # @param config [Configuration::Settings]
          # @param keep_alive [Numeric] seconds
          # @return [Link]
          # @raise [ConnectionError] when the handshake takes longer
          # @api private
          def self.open(config, keep_alive)
            tcp = Socket.tcp(config.mqtt_host, config.mqtt_port, connect_timeout: config.open_timeout)
            socket = OpenSSL::SSL::SSLSocket.new(tcp, context(config))
            socket.hostname = config.mqtt_host
            socket.sync_close = true
            new(handshake(socket, Process.clock_gettime(Process::CLOCK_MONOTONIC) + config.open_timeout), keep_alive)
          rescue StandardError
            (socket || tcp)&.close
            raise
          end

          # @param config [Configuration::Settings]
          # @return [OpenSSL::SSL::SSLContext]
          # @api private
          def self.context(config)
            OpenSSL::SSL::SSLContext.new.tap do |context|
              context.set_params(cert_store: OpenSSL::X509::Store.new.tap { it.add_file(config.mqtt_ca_file) })
              context.alpn_protocols = ['mqtt']
            end
          end

          # @param socket [OpenSSL::SSL::SSLSocket]
          # @param deadline [Float]
          # @return [OpenSSL::SSL::SSLSocket]
          # @raise [ConnectionError]
          # @api private
          def self.handshake(socket, deadline)
            loop do
              state = socket.connect_nonblock(exception: false)
              return socket unless %i[wait_readable wait_writable].include?(state)

              left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              ready = left.positive? && socket.to_io.public_send(state, left)
              raise ConnectionError, 'the TLS handshake with the Hue Secure broker took too long' unless ready
            end
          end
          private_class_method :context, :handshake

          # @param socket [OpenSSL::SSL::SSLSocket] connected
          # @param keep_alive [Numeric] seconds
          # @api private
          def initialize(socket, keep_alive)
            @socket = socket
            @keep_alive = keep_alive
            @buffer = +''.b
            @sent = clock
          end

          # @param type [Integer]
          # @param body [String]
          # @return [void]
          # @api private
          def write(type, body)
            @socket.write(Mqtt.packet(type, body))
            @sent = clock
          end

          # @param within [Numeric, nil] seconds to wait at most
          # @return [Array(Integer, String), nil] the first byte and the body of the next packet but a ping's answer;
          #   nil when the broker ends the connection between two packets
          # @raise [ConnectionError] when a ping gets no answer, or +within+ passes
          # @raise [EOFError] when the broker ends the connection within a packet
          # @api private
          def receive(within: nil)
            deadline = within && (clock + within)
            loop do
              packet = parsed
              next @pinged = false if packet && packet.first >> 4 == 13
              return packet if packet
              return finished if (chunk = @socket.read_nonblock(16_384, exception: false)).nil?

              chunk.is_a?(String) ? @buffer << chunk : wait(chunk, deadline)
            end
          end

          # Sends DISCONNECT, as the app does when it stops following, and closes.
          #
          # @return [void]
          # @api private
          def close
            @socket.write(Mqtt.packet(0xe0, ''))
          rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
            nil
          ensure
            @socket.close
          end

          private

          # @return [Array(Integer, String), nil]
          def parsed
            length, at = header
            return if length.nil? || at.nil? || @buffer.bytesize < at + length

            packet = [@buffer.getbyte(0).to_i, @buffer.byteslice(at, length).to_s] #: [Integer, String]
            @buffer = @buffer.byteslice((at + length)..).to_s
            packet
          end

          # @return [Array(Integer, Integer), nil] the remaining length and where the body starts; nil while incomplete
          def header
            length = shift = 0
            at = 1
            while (byte = @buffer.getbyte(at))
              length |= (byte & 0x7f) << shift
              shift += 7
              at += 1
              return [length, at] if byte < 0x80
            end
          end

          # @return [nil]
          # @raise [EOFError]
          def finished
            raise EOFError, 'the broker ended the connection within a packet' unless @buffer.empty?
          end

          # @param want [Symbol] +:wait_readable+ or +:wait_writable+
          # @param deadline [Float, nil]
          # @return [void]
          # @raise [ConnectionError]
          def wait(want, deadline)
            due = @sent + @keep_alive - clock
            return ping if due <= 0

            limit = deadline ? [due, deadline - clock].min : due
            raise ConnectionError, 'the Hue Secure broker did not answer in time' if limit <= 0

            @socket.to_io.public_send(want, limit)
          end

          # @return [void]
          # @raise [ConnectionError] when the ping before got no answer
          def ping
            raise ConnectionError, 'the Hue Secure broker did not answer a ping' if @pinged

            write(0xc0, '')
            @pinged = true
          end

          # @return [Float]
          def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
