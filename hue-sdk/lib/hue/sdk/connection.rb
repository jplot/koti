# frozen_string_literal: true

require 'net/http'
require 'openssl'

module Hue
  module Sdk
    # HTTPS transport to the bridge, pinned to the Hue root CA and to the
    # configured bridge id.
    module Connection
      NETWORK_ERRORS = [SocketError, SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout].freeze
      private_constant :NETWORK_ERRORS

      REQUESTS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze
      private_constant :REQUESTS

      module_function

      # Sends one request to the bridge.
      #
      # @param method [Symbol] +:get+, +:post+, +:put+ or +:delete+
      # @param path [String] absolute path on the bridge
      # @param body [String, nil] request body
      # @param headers [Hash{String=>String}] request headers
      # @return [Net::HTTPResponse]
      # @raise [TLSError] if the bridge certificate is not trusted
      # @raise [ConnectionError] if the bridge cannot be reached
      # @api public
      def request(method, path, body: nil, headers: {})
        request = REQUESTS.fetch(method).new(path, headers)
        request.body = body
        http.request(request)
      rescue OpenSSL::SSL::SSLError => e
        raise TLSError, "#{endpoint}: bridge #{Sdk.config.bridge_id} not verified (#{e.message})"
      rescue *NETWORK_ERRORS => e
        raise ConnectionError, "#{endpoint}: #{e.message}"
      end

      # Net::HTTP is not thread-safe: each thread keeps its own keep-alive
      # connection, renewed when the bridge settings change.
      #
      # @return [Net::HTTP] a started keep-alive connection
      # @api private
      def http = (Thread.current[:hue_sdk_connections] ||= {})[connection_key] ||= establish

      # @return [Array] the settings a connection is bound to
      # @api private
      def connection_key = Sdk.config.then { |config| [config.host, config.port, config.bridge_id, config.ca_file] }

      # @return [Net::HTTP]
      # @api private
      def establish
        config = Sdk.config
        host = config.host or raise ConnectionError, 'host is not configured'
        http = Net::HTTP.new(host, config.port)
        pin(http, config)
        http.open_timeout = config.open_timeout
        http.read_timeout = config.read_timeout
        http.start
      end

      # Trusts only the configured CA, and only a leaf carrying the bridge id.
      #
      # @param http [Net::HTTP]
      # @param config [Configuration::Settings]
      # @return [void]
      # @api private
      def pin(http, config)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_hostname = false
        http.cert_store = OpenSSL::X509::Store.new.tap { |store| store.add_file(config.ca_file) }
        http.verify_callback = identity_check(config.bridge_id)
      end

      # @param bridge_id [String, nil]
      # @return [Proc] verify callback accepting only a leaf whose CN is +bridge_id+
      # @api private
      def identity_check(bridge_id)
        lambda do |preverified, context|
          next preverified unless context.error_depth.zero?
          next false unless preverified && bridge_id

          common_name = context.current_cert.subject.to_a.find { |name, _, _| name == 'CN' }&.at(1).to_s
          common_name.casecmp?(bridge_id) == true
        end
      end

      # @return [String] +host:port+ of the configured bridge
      # @api private
      def endpoint = "#{Sdk.config.host}:#{Sdk.config.port}"
    end
  end
end
