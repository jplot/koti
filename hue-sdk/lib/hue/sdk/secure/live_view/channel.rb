# frozen_string_literal: true

require 'openssl'
require 'socket'
require 'uri'

module Hue
  module Sdk
    module Secure
      class LiveView
        # The WebSocket of a signaling channel, over TLS: writes from any thread go one at a time, the reads on the
        # caller's thread, and no thread of its own.
        class Channel
          ERRORS = [IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError].freeze
          private_constant :ERRORS

          Wire = Data.define(:url, :io)
          private_constant :Wire

          # What websocket-driver reads the URL from, and writes to.
          class Wire
            # @param data [String]
            # @return [Integer]
            def write(data) = io.write(data)
          end

          # @param url [String] presigned
          # @raise [ResponseError] if Kinesis Video refuses the URL
          # @raise [ConnectionError] if it cannot be reached
          # @api private
          def initialize(url)
            @lock = Mutex.new
            @inbox = []
            connect(url)
          rescue *ERRORS => e
            raise ConnectionError, "Kinesis Video: #{e.message}"
          end

          # @return [String] without the presigned URL, which carries the session token
          def inspect = "#<#{self.class.name}>"

          # @param text [String]
          # @return [void]
          # @raise [ConnectionError] if the channel is closed
          # @api private
          def write(text)
            raise ConnectionError, 'the signaling channel is closed' unless @lock.synchronize { @driver.text(text) }
          rescue *ERRORS => e
            raise ConnectionError, "Kinesis Video: #{e.message}"
          end

          # Reads until {#close}.
          #
          # @yieldparam text [String] a message of the channel
          # @return [void]
          # @raise [ConnectionError] if Kinesis Video closes the channel or drops the connection
          # @api private
          def each_text
            loop do
              yield @inbox.shift until @inbox.empty?
              raise ConnectionError, 'Kinesis Video closed the signaling channel' if @ended && !@closed

              data = received or break
              @lock.synchronize { @driver.parse(data) }
            end
          rescue ConnectionError
            @tcp.close
            raise
          end

          # @return [void]
          # @api private
          def close
            @closed = true
            farewell
          ensure
            # The TCP socket, not the TLS one: closing that first flushes a stuck writer's bytes to a peer that no
            # longer reads, and waits with it (seen on Linux).
            @tcp.close
          end

          private

          def connect(url)
            @socket = socket(URI(url))
            @driver = WebSocket::Driver.client(Wire.new(url:, io: @socket))
            @driver.on(:message) { @inbox << it.data }
            @driver.on(:close) { @ended = true }
            @driver.start
            handshake
            opened = true
          ensure
            @tcp&.close unless opened
          end

          # A writer that waits on a peer which stopped reading holds the lock: the socket then closes without the
          # close frame, and the writer's wait ends.
          def farewell
            return unless @lock.try_lock

            begin
              @driver.close
            ensure
              @lock.unlock
            end
          rescue *ERRORS
            nil
          end

          def socket(uri)
            config = Secure.config
            @tcp = Socket.tcp(uri.host.to_s, uri.port.to_i, connect_timeout: config.open_timeout)
            @tcp.timeout = config.read_timeout
            tls(uri.host.to_s)
          end

          def tls(host)
            OpenSSL::SSL::SSLSocket.new(@tcp, OpenSSL::SSL::SSLContext.new.tap(&:set_params)).tap do |tls|
              tls.hostname = host
              tls.sync_close = true
              tls.connect
            end
          end

          def handshake
            @driver.parse(@socket.readpartial(16_384)) while @driver.state == :connecting
            unless @driver.state == :open
              raise ResponseError.new(@driver.status.to_i, ['the signaling URL is refused'], source: 'Kinesis Video')
            end

            @tcp.timeout = nil
          end

          def received
            @socket.readpartial(16_384)
          rescue *ERRORS => e
            raise ConnectionError, "Kinesis Video: #{e.message}" unless @closed
          end
        end
      end
    end
  end
end
