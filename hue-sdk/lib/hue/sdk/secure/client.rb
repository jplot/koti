# frozen_string_literal: true

require 'json'
require 'uri'

module Hue
  module Sdk
    module Secure
      # Requests to the Hue account's cloud with the session's token: every path stays reachable without a typed
      # class.
      #
      # @example Read the arm state of a home
      #   Hue::Sdk::Secure.client.get("security/arm-manager/v1/home/#{home.id}/arm/state").body
      class Client
        # @param session [Session]
        # @api public
        def initialize(session)
          @session = session
        end

        # @param path [String] path under +api_url+, or an absolute address
        # @param query [Hash{String, Symbol=>Object}]
        # @param headers [Hash{String=>String}]
        # @return [Http::Response]
        # @raise (see Http.request)
        # @api public
        def get(path, query: {}, headers: {}) = request(:get, path, nil, query, headers)

        # @param path [String] path under +api_url+, or an absolute address
        # @param body [Object, nil] sent as JSON
        # @param query [Hash{String, Symbol=>Object}]
        # @param headers [Hash{String=>String}]
        # @return [Http::Response]
        # @raise (see Http.request)
        # @api public
        def post(path, body: nil, query: {}, headers: {}) = request(:post, path, body, query, headers)

        # @param path [String] path under +api_url+, or an absolute address
        # @param body [Object, nil] sent as JSON
        # @param query [Hash{String, Symbol=>Object}]
        # @param headers [Hash{String=>String}]
        # @return [Http::Response]
        # @raise (see Http.request)
        # @api public
        def put(path, body: nil, query: {}, headers: {}) = request(:put, path, body, query, headers)

        # @param path [String] path under +api_url+, or an absolute address
        # @param query [Hash{String, Symbol=>Object}]
        # @param headers [Hash{String=>String}]
        # @return [Http::Response]
        # @raise (see Http.request)
        # @api public
        def delete(path, query: {}, headers: {}) = request(:delete, path, nil, query, headers)

        private

        # The app names JSON on every +security/+ request, GET and DELETE included, and on a body for the others.
        #
        # @param method [Symbol]
        # @param path [String]
        # @param body [Object, nil]
        # @param query [Hash{String, Symbol=>Object}]
        # @param headers [Hash{String=>String}]
        # @return [Http::Response]
        def request(method, path, body, query, headers)
          url = path.start_with?('https://', 'http://') ? path : "#{Secure.config.api_url}/#{path}"
          url = "#{url}?#{URI.encode_www_form(query)}" unless query.empty?
          sent = { 'Authorization' => "Bearer #{@session.current.value}" }
          sent['Content-Type'] = 'application/json' if !body.nil? || path.start_with?('security/')
          Http.request(method, url, headers: sent.merge(headers), body: (JSON.generate(body) unless body.nil?))
        end
      end
    end
  end
end
