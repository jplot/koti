# frozen_string_literal: true

require 'net/http'
require 'uri'

module Miele
  module Sdk
    module Cloud
      # Plain exchanges with the Miele cloud: no household key, the account's token is a header.
      module Http
        REQUESTS = { get: Net::HTTP::Get, put: Net::HTTP::Put, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.freeze
        private_constant :REQUESTS

        NETWORK_ERRORS = [SocketError, SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout,
                          OpenSSL::SSL::SSLError].freeze
        private_constant :NETWORK_ERRORS

        # An answer of the cloud.
        #
        # @!attribute [r] status
        #   @return [Integer] HTTP status
        # @!attribute [r] body
        #   @return [String]
        Response = Data.define(:status, :body)

        module_function

        # @param method [Symbol] +:get+, +:put+, +:post+ or +:delete+
        # @param url [String] absolute address, query included
        # @param headers [Hash{String=>String}]
        # @param body [String, nil]
        # @return [Response]
        # @raise [ConnectionError] if the cloud cannot be reached
        # @api public
        def request(method, url, headers: {}, body: nil)
          uri = URI(url) #: URI::HTTP
          request = REQUESTS.fetch(method).new(uri.request_uri)
          { 'User-Agent' => "miele-sdk/#{VERSION}", **headers }.each { |name, value| request[name] = value }
          request.body = body if body
          answer = exchange(uri, request)
          Response.new(status: answer.code.to_i, body: answer.body.to_s)
        end

        # @param uri [URI::Generic]
        # @param request [Net::HTTPRequest]
        # @return [Net::HTTPResponse]
        # @raise [ConnectionError]
        # @api private
        def exchange(uri, request)
          config = Sdk.config
          host = uri.host.to_s
          options = { use_ssl: uri.scheme == 'https', open_timeout: config.open_timeout,
                      read_timeout: config.read_timeout }
          Net::HTTP.start(host, uri.port, **options) { |http| http.request(request) }
        rescue *NETWORK_ERRORS => e
          raise ConnectionError, "#{host}: #{e.message}"
        end
      end
    end
  end
end
