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
      LIMITERS = Mutex.new
      private_constant :REQUESTS, :LIMITERS

      # Net::HTTP checks a reused connection for an end of stream before writing the next request, and OpenSSL
      # raises there when the bridge closed it without close_notify: nothing was sent yet, so it reconnects.
      class KeepAlive < Net::HTTP
        private

        # @param request [Net::HTTPRequest]
        # @return [void]
        # @api private
        def begin_transport(request)
          if closed_abruptly?
            @socket.close
            connect
          end
          super
        end

        # @return [Boolean]
        # @api private
        def closed_abruptly?
          @socket.eof? if !@socket.closed? && @socket.io.to_io.wait_readable(0)
          false
        rescue OpenSSL::SSL::SSLError, SystemCallError, IOError
          true
        end
      end
      private_constant :KeepAlive

      module_function

      # Sends one request to the bridge. After a 429 on the same path, it first waits up to 30 s, as the app does.
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
        limited(path) { transport { http.request(request) } }
      end

      # @param path [String]
      # @yieldreturn [Net::HTTPResponse]
      # @return [Net::HTTPResponse]
      # @api private
      def limited(path, &)
        connection = connection_key
        limiter = LIMITERS.synchronize do
          @limiters ||= {} #: Hash[untyped, RateLimiter]
          @limiters[connection] ||= RateLimiter.new
        end
        limiter.through("#{connection.first}#{path.split('?').first}", &)
      end

      # Opens a long-lived request and passes its body on as it arrives. The
      # stream gets a connection of its own: a request sent from the block on
      # the thread's connection would read the rest of the stream as its answer.
      #
      # @param path [String] absolute path on the bridge
      # @param headers [Hash{String=>String}] request headers
      # @yieldparam chunk [String] body bytes, cut anywhere, when the bridge answers 200
      # @return [Net::HTTPResponse] once the bridge ends the response
      # @raise [TLSError] if the bridge certificate is not trusted
      # @raise [ConnectionError] if the bridge cannot be reached or the stream breaks
      # @api public
      def stream(path, headers: {}, &)
        transport do
          http = establish(Sdk.config.event_read_timeout)
          http.request(Net::HTTP::Get.new(path, headers)) do |response|
            response.read_body(&) if response.is_a?(Net::HTTPOK)
          end
        ensure
          http&.finish if http&.started?
        end
      end

      # OpenSSL also raises SSLError when the bridge drops a connection without
      # close_notify, as it does to an event stream idle for 5 minutes: only a
      # failed verification means the peer is not the configured bridge.
      #
      # @yieldreturn [Object] the result of the exchange with the bridge
      # @return [Object] what the block returns
      # @raise [TLSError] if the bridge certificate is not trusted
      # @raise [ConnectionError] if the bridge cannot be reached or drops the connection
      # @api private
      def transport
        yield
      rescue OpenSSL::SSL::SSLError => e
        raise ConnectionError, "#{endpoint}: #{e.message}" unless e.message.include?('certificate verify failed')

        raise TLSError, "#{endpoint}: bridge #{Sdk.config.bridge_id} not verified (#{e.message})"
      rescue *NETWORK_ERRORS => e
        raise ConnectionError, "#{endpoint}: #{e.message}"
      end

      # Net::HTTP is not thread-safe: each thread, and each fiber within it, keeps
      # its own keep-alive connection, renewed when the bridge settings change.
      #
      # @return [Net::HTTP] a started keep-alive connection
      # @api private
      def http = (Thread.current[:hue_sdk_connections] ||= {})[connection_key] ||= establish

      # @return [Array] the settings a connection is bound to
      # @api private
      def connection_key = Sdk.config.then { |config| [config.host, config.port, config.bridge_id, config.ca_file] }

      # @param read_timeout [Numeric] seconds to wait for data
      # @return [Net::HTTP]
      # @api private
      def establish(read_timeout = Sdk.config.read_timeout)
        config = Sdk.config
        host = config.host or raise ConnectionError, 'host is not configured'
        config.bridge_id or raise TLSError, 'bridge_id is not configured'
        # nil is the proxy: an http_proxy set for the Internet would otherwise tunnel every bridge request.
        http = KeepAlive.new(host, config.port, nil)
        pin(http, config)
        http.open_timeout = config.open_timeout
        http.read_timeout = read_timeout
        # The app sends a bridge request once, whatever fails; Net::HTTP would send a GET, PUT or DELETE again
        # after a dropped connection or a read timeout.
        http.max_retries = 0
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
