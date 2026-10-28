# frozen_string_literal: true

require 'io/nonblock'
require 'socket'

module Hue
  module Sdk
    module Entertainment
      # DTLS 1.2 client socket authenticated by a pre-shared key, as the
      # bridge expects for entertainment streaming.
      class DtlsSocket
        CIPHER = 'PSK-AES128-GCM-SHA256'
        private_constant :CIPHER

        HANDSHAKE_TIMEOUT = 5
        private_constant :HANDSHAKE_TIMEOUT

        # @param host [String] bridge address
        # @param identity [String] PSK identity: the application key
        # @param psk [String] raw pre-shared key: the client key decoded from hex
        # @param port [Integer] entertainment port of the bridge
        # @return [DtlsSocket] a socket whose handshake succeeded
        # @raise [ConnectionError] if the handshake fails or gets no answer within 5 seconds
        # @api public
        def self.open(host:, identity:, psk:, port: 2100) = new(host, port, identity, psk).tap(&:handshake)

        # @param host [String]
        # @param port [Integer]
        # @param identity [String]
        # @param psk [String]
        # @api private
        def initialize(host, port, identity, psk)
          @endpoint = "#{host}:#{port}"
          @socket = blocking_socket(host, port)
          @callback = LibSSL.psk_callback(identity, psk)
          @context = LibSSL.SSL_CTX_new(LibSSL.DTLS_client_method)
          LibSSL.SSL_CTX_set_cipher_list(@context, CIPHER)
          LibSSL.SSL_CTX_set_psk_client_callback(@context, @callback)
          @ssl = LibSSL.SSL_new(@context)
          LibSSL.SSL_set_fd(@ssl, @socket.fileno)
        end

        # @return [void]
        # @raise [ConnectionError] if the handshake fails
        # @api private
        def handshake
          result = LibSSL.SSL_connect(@ssl)
          return if result == 1

          error = LibSSL.SSL_get_error(@ssl, result)
          close
          raise ConnectionError, "#{@endpoint}: DTLS handshake failed (SSL error #{error})"
        end

        # @param data [String] one message, sent as one datagram
        # @return [Integer] bytes written
        # @raise [IOError] once the socket is closed
        # @raise [ConnectionError] if the write fails
        # @api public
        def write(data)
          raise IOError, "#{@endpoint}: DTLS socket closed" unless @ssl

          written = LibSSL.SSL_write(@ssl, data, data.bytesize)
          return written if written.positive?

          raise ConnectionError, "#{@endpoint}: DTLS write failed (SSL error #{LibSSL.SSL_get_error(@ssl, written)})"
        end

        # Sends close_notify and releases the socket; later calls do nothing.
        #
        # @return [void]
        # @api public
        def close
          return unless @ssl

          LibSSL.SSL_shutdown(@ssl)
          LibSSL.SSL_free(@ssl)
          LibSSL.SSL_CTX_free(@context)
          @socket.close
          @ssl = nil
        end

        private

        # Ruby opens sockets with O_NONBLOCK: libssl's recv would return EAGAIN
        # at once and SSL_connect give up before the bridge answers.
        #
        # @param host [String]
        # @param port [Integer]
        # @return [UDPSocket] connected, blocking, reads time out after 5 seconds
        # @api private
        def blocking_socket(host, port)
          timeval = [HANDSHAKE_TIMEOUT, 0].pack('l_2')
          UDPSocket.new.tap do |socket|
            socket.connect(host, port)
            socket.nonblock = false # steep:ignore NoMethod
            socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, timeval) # steep:ignore ArgumentTypeMismatch
          rescue SocketError, SystemCallError => e
            socket.close
            raise ConnectionError, "#{@endpoint}: #{e.message}"
          end
        end
      end
    end
  end
end
