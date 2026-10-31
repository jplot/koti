# frozen_string_literal: true

require 'digest'
require 'openssl'
require 'securerandom'
require 'socket'

module Miele
  module Sdk
    module Cloud
      class Websocket
        # The opening handshake as the app's Websocket.Client makes it: the session's +Authorization+ and
        # +Accept-Language+, and the +mielecloudconnect+ sub-protocol.
        module Handshake
          GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
          private_constant :GUID

          private

          # @return [IO] the open connection
          # @raise [ConnectionError] unless the cloud switches protocols with the key's answer
          def connect
            token = @session.current
            tcp = Socket.tcp(@url.host.to_s, @url.port.to_i, connect_timeout: 10)
            socket = @url.scheme == 'wss' ? tls(tcp) : tcp
            key = [SecureRandom.random_bytes(16)].pack('m0')
            socket.write(request(key, token))
            check(socket, key, token)
            socket
          end

          # @param tcp [Socket]
          # @return [OpenSSL::SSL::SSLSocket]
          def tls(tcp)
            context = OpenSSL::SSL::SSLContext.new
            context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
            socket = OpenSSL::SSL::SSLSocket.new(tcp, context)
            socket.hostname = @url.host.to_s
            socket.sync_close = true
            socket.connect
          end

          # @param key [String]
          # @param token [Token]
          # @return [String]
          def request(key, token)
            host = @url.port == @url.default_port ? @url.host : "#{@url.host}:#{@url.port}"
            ["GET #{@url.path} HTTP/1.1", "Host: #{host}", 'Upgrade: websocket', 'Connection: Upgrade',
             "Sec-WebSocket-Key: #{key}", 'Sec-WebSocket-Version: 13', 'Sec-WebSocket-Protocol: mielecloudconnect',
             "Authorization: #{token.scheme} #{token.value}", "Accept-Language: #{@session.language}", '',
             ''].join("\r\n")
          end

          # A refused token is renewed for the next attempt, as {Channel#request} renews it.
          #
          # @param socket [IO]
          # @param key [String]
          # @param token [Token] the token sent
          # @return [void]
          # @raise [ConnectionError]
          def check(socket, key, token)
            status = socket.gets("\r\n").to_s
            accepted = response_headers(socket)['sec-websocket-accept'] == [Digest::SHA1.digest(key + GUID)].pack('m0')
            return if status.include?(' 101 ') && accepted

            @session.renew(token) if status.include?(' 401 ')
            raise ConnectionError, "the cloud websocket answered #{status.strip}"
          end

          # @param socket [IO]
          # @return [Hash{String=>String}] by lower-case name
          def response_headers(socket)
            headers = {} #: Hash[String, String]
            while (line = socket.gets("\r\n")) && line != "\r\n"
              name, value = line.chomp.split(': ', 2)
              headers[name.to_s.downcase] = value.to_s
            end
            headers
          end
        end
      end
    end
  end
end
