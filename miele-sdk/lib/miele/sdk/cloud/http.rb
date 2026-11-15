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
        # @param timeout [Numeric, nil] as {Connection.request} takes it
        # @return [Response]
        # @raise [ConnectionError] if the cloud cannot be reached
        # @api public
        def request(method, url, headers: {}, body: nil, timeout: nil)
          uri = URI(url) #: URI::HTTP
          request = REQUESTS.fetch(method).new(uri.request_uri)
          { 'User-Agent' => "miele-sdk/#{VERSION}", **headers }.each { |name, value| request[name] = value }
          # AndroidMessageHandler.SetupRequestBody sends a POST, PUT or DELETE without content as Content-Length: 0;
          # Net::HTTP does it for a POST or a PUT only.
          request.body = body || '' unless method == :get
          answer = exchange(uri, request, timeout)
          Response.new(status: answer.code.to_i, body: answer.body.to_s)
        end

        # @param uri [URI::Generic]
        # @param request [Net::HTTPRequest]
        # @param timeout [Numeric, nil]
        # @return [Net::HTTPResponse]
        # @raise [ConnectionError]
        # @api private
        def exchange(uri, request, timeout = nil)
          config = Sdk.config
          host = uri.host.to_s
          # The app sends a cloud request once, whatever fails (MieleHttpClientHandler, no retry); Net::HTTP would
          # send a GET, PUT or DELETE again after a dropped connection or a read timeout.
          options = { use_ssl: uri.scheme == 'https', **config.timeouts(timeout), max_retries: 0 }
          Net::HTTP.start(host, uri.port, **options) { |http| http.request(request) }
        rescue *NETWORK_ERRORS => e
          raise ConnectionError, "#{host}: #{e.message}"
        end
      end
    end
  end
end
