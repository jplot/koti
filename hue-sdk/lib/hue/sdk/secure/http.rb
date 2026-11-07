# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

module Hue
  module Sdk
    module Secure
      # Plain exchanges with the Hue account's cloud, which answers with a certificate of the public web.
      module Http
        REQUESTS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze
        private_constant :REQUESTS

        NETWORK_ERRORS = [SocketError, SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout,
                          OpenSSL::SSL::SSLError].freeze
        private_constant :NETWORK_ERRORS

        ERRORS = { 404 => NotFoundError, 429 => RateLimitError }.freeze
        private_constant :ERRORS

        # An answer of the cloud.
        #
        # @!attribute [r] status
        #   @return [Integer] HTTP status, from 200 to 206
        # @!attribute [r] body
        #   @return [Object, nil] the parsed JSON, the text of any other answer, nil when empty
        # @!attribute [r] headers
        #   @return [Hash{String=>String}] by lowercase name
        Response = Data.define(:status, :body, :headers)

        module_function

        # @param method [Symbol] +:get+, +:post+, +:put+ or +:delete+
        # @param url [String] absolute address, query included
        # @param headers [Hash{String=>String}]
        # @param body [String, nil]
        # @return [Response]
        # @raise [ConnectionError] if the cloud cannot be reached
        # @raise [AuthenticationError] on 401 and 403
        # @raise [ResponseError] on any other status outside 200 to 206: 207 and 521 too
        # @api private
        def request(method, url, headers: {}, body: nil)
          uri = URI(url) #: URI::HTTP
          request = REQUESTS.fetch(method).new(uri, { 'User-Agent' => "hue-sdk/#{VERSION}", **headers })
          request.body = body
          answer = exchange(uri, request)
          response = Response.new(status: answer.code.to_i, body: parse(answer), headers: answer.each_header.to_h)
          response.status.between?(200, 206) ? response : refuse(response)
        end

        # @param uri [URI::HTTP]
        # @param request [Net::HTTPRequest]
        # @return [Net::HTTPResponse]
        # @raise [ConnectionError]
        # @api private
        def exchange(uri, request)
          config = Secure.config
          options = { use_ssl: uri.scheme == 'https', open_timeout: config.open_timeout,
                      read_timeout: config.read_timeout }
          Net::HTTP.start(uri.host.to_s, uri.port, **options) { it.request(request) }
        rescue *NETWORK_ERRORS => e
          raise ConnectionError, "#{uri.host}: #{e.message}"
        end

        # @param answer [Net::HTTPResponse]
        # @return [Object, nil]
        # @api private
        def parse(answer)
          text = answer.body.to_s
          return if text.empty?
          return text unless answer.content_type.to_s.include?('json')

          JSON.parse(text)
        rescue JSON::ParserError
          text
        end

        # @param response [Response]
        # @return [bot]
        # @raise [AuthenticationError, ResponseError]
        # @api private
        def refuse(response)
          status = response.status
          messages = descriptions(response.body)
          if [401, 403].include?(status)
            raise AuthenticationError, "the Hue account refused the token (#{status}: #{messages.join('; ')})"
          end

          raise ERRORS.fetch(status, ResponseError).new(status, messages, source: 'Hue cloud')
        end

        # Auth0 describes a refusal in +error_description+, the data API in +errors[].message+.
        #
        # @param body [Object, nil]
        # @return [Array<String>]
        # @api private
        def descriptions(body)
          return [*body['errors']&.map { it['message'] }, body['error_description']].compact if body.is_a?(Hash)

          [] #: Array[String]
        end
      end
    end
  end
end
