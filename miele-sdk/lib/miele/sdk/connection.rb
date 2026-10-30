# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'time'

module Miele
  module Sdk
    # Signed and encrypted HTTP exchanges with an appliance (MieleH256). Every
    # response that carries a body must be signed by the household key.
    module Connection
      ACCEPT = 'application/vnd.miele.v1+json'
      private_constant :ACCEPT

      # Signed as part of the request: the spaces are the ones appliances accept.
      CONTENT_TYPE = 'application / vnd.miele.v1 + json; charset = utf - 8'
      private_constant :CONTENT_TYPE

      REQUESTS = { get: Net::HTTP::Get, put: Net::HTTP::Put, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.freeze
      private_constant :REQUESTS

      NETWORK_ERRORS = [SocketError, SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout].freeze
      private_constant :NETWORK_ERRORS

      # An appliance's answer.
      #
      # @!attribute [r] status
      #   @return [Integer] HTTP status
      # @!attribute [r] body
      #   @return [String] decrypted body, padding spaces included, or empty
      Response = Data.define(:status, :body)

      # The appliance itself as a channel: requests go to it signed and encrypted with the household key.
      #
      # @!attribute [r] host
      #   @return [String] address or +.local+ name of the appliance
      Local = Data.define(:host)

      # The appliance itself as a channel.
      class Local
        # The reference pads every DOP2 write to 32 bytes; shorter ones were never tried on an appliance.
        #
        # @param method [Symbol] +:get+, +:put+, +:post+ or +:delete+
        # @param path [String] absolute path, query included
        # @param body [String, nil]
        # @param kind [Symbol] +:json+ or +:dop2+
        # @return [Response]
        # @raise [Error] see {Connection.request}
        def request(method, path, body: nil, kind: :json, **)
          Connection.request(host, method, path, body: kind == :dop2 ? body&.ljust(32, ' ') : body)
        end
      end

      module_function

      # @param host [String] address or +.local+ name of the appliance
      # @return [Local]
      # @api public
      def local(host) = Local.new(host:)

      # Sends one request to an appliance.
      #
      # @param host [String] address or +.local+ name of the appliance
      # @param method [Symbol] +:get+, +:put+, +:post+ or +:delete+
      # @param path [String] absolute path, query included
      # @param body [String, nil] plaintext body, sent encrypted
      # @return [Response]
      # @raise [ConfigurationError] if the household key is missing or malformed
      # @raise [ConnectionError] if the appliance cannot be reached
      # @raise [SignatureError] if the response is not signed by the household key
      # @raise [AuthenticationError, ResponseError] if the appliance answers with an error status
      # @api public
      def request(host, method, path, body: nil)
        group_id, key = credentials
        message = sign(REQUESTS.fetch(method).new(path), host, body ? Crypto.pad(body) : '', group_id, key)
        answer(exchange(host, message), method, key)
      end

      # @return [Array(String, String)] GroupID and GroupKey, as bytes
      # @raise [ConfigurationError]
      # @api private
      def credentials
        group_id = Sdk.config.group_id.to_s
        group_key = Sdk.config.group_key.to_s
        raise ConfigurationError, 'group_id must be 16 hexadecimal digits' unless group_id.match?(/\A\h{16}\z/)
        raise ConfigurationError, 'group_key must be 128 hexadecimal digits' unless group_key.match?(/\A\h{128}\z/)

        [[group_id].pack('H*'), [group_key].pack('H*')]
      end

      # @param request [Net::HTTPRequest]
      # @param host [String]
      # @param plaintext [String] padded body, empty without one
      # @param group_id [String]
      # @param key [String]
      # @return [Net::HTTPRequest] the request, signed and with its body encrypted
      # @api private
      def sign(request, host, plaintext, group_id, key)
        date = Time.now.httpdate
        content_type = plaintext.empty? ? '' : CONTENT_TYPE
        lines = [request.method, "#{host}#{request.path}", content_type, ACCEPT, date]
        signature = Crypto.signature(key:, lines:, body: plaintext)
        { 'Accept' => ACCEPT, 'Date' => date, 'Host' => host, 'User-Agent' => "miele-sdk/#{VERSION}",
          'Authorization' => Crypto.authorization(group_id:, signature:) }.each { |name, value| request[name] = value }
        encrypt(request, content_type, key, signature, plaintext)
      end

      # @param request [Net::HTTPRequest]
      # @param content_type [String]
      # @param key [String]
      # @param signature [String]
      # @param plaintext [String]
      # @return [Net::HTTPRequest]
      # @api private
      def encrypt(request, content_type, key, signature, plaintext)
        return request if plaintext.empty?

        request['Content-Type'] = content_type
        request.body = Crypto.encrypt(key:, signature:, plaintext:)
        request
      end

      # @param host [String]
      # @param request [Net::HTTPRequest]
      # @return [Net::HTTPResponse]
      # @raise [ConnectionError]
      # @api private
      def exchange(host, request)
        config = Sdk.config
        timeouts = { open_timeout: config.open_timeout, read_timeout: config.read_timeout }
        # nil is the proxy: an http_proxy set for the Internet would otherwise receive every LAN request.
        Net::HTTP.start(host, config.port, nil, **timeouts) { |http| http.request(request) }
      rescue *NETWORK_ERRORS => e
        raise ConnectionError, "#{host}:#{config&.port}: #{e.message}"
      end

      # @param response [Net::HTTPResponse]
      # @param method [Symbol]
      # @param key [String]
      # @return [Response]
      # @api private
      def answer(response, method, key)
        status = response.code.to_i
        refuse(status, method) unless (200..299).cover?(status)
        body = response.body.to_s
        Response.new(status:, body: body.empty? ? '' : decrypt(response, status, body, key))
      end

      # @param response [Net::HTTPResponse]
      # @param status [Integer]
      # @param body [String]
      # @param key [String]
      # @return [String] plaintext, padding spaces included
      # @raise [SignatureError]
      # @api private
      def decrypt(response, status, body, key)
        signature = [response['X-Signature'].to_s.split(':', 2).last.to_s].pack('H*')
        raise SignatureError, 'response not signed by the household key' unless signature.bytesize == 32

        plaintext = Crypto.decrypt(key:, signature:, ciphertext: body)
        lines = [status, response['Content-Type'], response['Date']]
        return plaintext if OpenSSL.secure_compare(Crypto.signature(key:, lines:, body: plaintext), signature)

        raise SignatureError, 'response not signed by the household key'
      rescue OpenSSL::Cipher::CipherError
        raise SignatureError, 'response not encrypted with the household key'
      end

      # @param status [Integer]
      # @param method [Symbol]
      # @return [void]
      # @raise [AuthenticationError, NotFoundError, RemoteControlDisabledError, ResponseError]
      # @api private
      def refuse(status, method)
        raise NotFoundError, status if status == 404
        raise ResponseError, status unless status == 403
        raise AuthenticationError, 'appliance refused the signature: check group_id and group_key' if method == :get

        raise RemoteControlDisabledError.new(
          status, 'appliance refused the command: enable Mobile Controllable on it (a wrong group_key also gives 403)'
        )
      end
    end
  end
end
