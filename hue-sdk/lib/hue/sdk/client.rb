# frozen_string_literal: true

require 'json'
require 'singleton'

module Hue
  module Sdk
    # Singleton entry point to the CLIP v2 API of the bridge.
    #
    # Unwraps the +{"data": [...], "errors": [...]}+ envelope and maps error
    # statuses to exceptions. HTTP methods are available on both the instance
    # and the class.
    #
    # @example Read every light
    #   Hue::Sdk::Client.get('/resource/light')
    #
    # @example Switch a light off
    #   Hue::Sdk::Client.put('/resource/light/1a2b', body: { on: { on: false } })
    class Client
      include Singleton

      ERRORS = { 404 => NotFoundError, 429 => RateLimitError }.freeze
      private_constant :ERRORS

      # Reads resources.
      #
      # @param path [String] path relative to +/clip/v2+
      # @return [Array<Hash{String=>Object}>] the +data+ of the response
      # @api public
      def get(path) = call(:get, path)

      # Creates a resource.
      #
      # @param path [String] path relative to +/clip/v2+
      # @param body [Hash] attributes of the resource
      # @return [Array<Hash{String=>Object}>] references (+rid+, +rtype+) of what was created
      # @api public
      def post(path, body:) = call(:post, path, body)

      # Updates a resource.
      #
      # @param path [String] path relative to +/clip/v2+
      # @param body [Hash] attributes to change
      # @return [Array<Hash{String=>Object}>] references (+rid+, +rtype+) of what was updated
      # @api public
      def put(path, body:) = call(:put, path, body)

      # Deletes a resource.
      #
      # @param path [String] path relative to +/clip/v2+
      # @return [Array<Hash{String=>Object}>] references (+rid+, +rtype+) of what was deleted
      # @api public
      def delete(path) = call(:delete, path)

      class << self
        # @see #get
        # @api public
        def get(path) = instance.get(path)

        # @see #post
        # @api public
        def post(path, body:) = instance.post(path, body:)

        # @see #put
        # @api public
        def put(path, body:) = instance.put(path, body:)

        # @see #delete
        # @api public
        def delete(path) = instance.delete(path)
      end

      private

      # @param method [Symbol]
      # @param path [String]
      # @param body [Hash, nil]
      # @return [Array<Hash{String=>Object}>]
      # @raise [AuthenticationError] if no application key is configured or the bridge rejects it
      # @raise [ResponseError] if the bridge answers with an error status
      # @api private
      def call(method, path, body = nil)
        key = Sdk.config.application_key or raise AuthenticationError, 'application_key is not configured'
        headers = { 'hue-application-key' => key }
        headers['Content-Type'] = 'application/json' if body
        unwrap(Connection.request(method, "/clip/v2#{path}", body: body && JSON.generate(body), headers:))
      end

      # @param response [Net::HTTPResponse]
      # @return [Array<Hash{String=>Object}>]
      # @api private
      def unwrap(response)
        status = response.code.to_i
        payload = parse(response.body)
        return payload.fetch('data', []) if status == 200
        raise AuthenticationError, "bridge rejected the application key (#{status})" if [401, 403].include?(status)

        raise ERRORS.fetch(status, ResponseError).new(status, payload.fetch('errors', []).map { it['description'] })
      end

      # @param body [String, nil]
      # @return [Hash{String=>Object}] the parsed envelope, empty when the body is not JSON
      # @api private
      def parse(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
