# frozen_string_literal: true

require 'json'

module Hue
  module Sdk
    Settings = Data.define(:name, :bridge_id, :model_id, :software_version, :api_version, :time_zone, :utc,
                           :remote_access, :analytics_consent, :http_blocked)

    # The settings of the bridge the Hue app reads and writes over CLIP v1. CLIP v2 only reports the time zone, and the
    # app reads it there.
    #
    # @!attribute [r] name
    #   @return [String, nil] name of the bridge
    # @!attribute [r] bridge_id
    #   @return [String, nil]
    # @!attribute [r] model_id
    #   @return [String, nil]
    # @!attribute [r] software_version
    #   @return [String, nil]
    # @!attribute [r] api_version
    #   @return [String, nil]
    # @!attribute [r] time_zone
    #   @return [String, nil] such as +Europe/Paris+, one of {.time_zones}
    # @!attribute [r] utc
    #   @return [String, nil] the clock of the bridge, such as +2026-11-03T10:00:00+
    # @!attribute [r] remote_access
    #   @return [Boolean, nil] whether the bridge may reach the Hue cloud; the app sets it when pairing only
    # @!attribute [r] analytics_consent
    #   @return [Boolean, nil] whether the bridge may share statistics
    # @!attribute [r] http_blocked
    #   @return [Boolean, nil] whether the bridge refuses plain HTTP; not every bridge reports it
    class Settings
      WRITE = { time_zone: 'timezone', utc: 'UTC', http_blocked: 'blockhttp',
                analytics_consent: 'analyticsconsent' }.freeze
      private_constant :WRITE

      # Reads the settings of the bridge.
      #
      # @return [Settings]
      # @raise [AuthenticationError] if no application key is configured or the bridge rejects it
      # @raise [ResponseError] if the bridge refuses
      # @api public
      def self.read
        config = ClipV1.object('config')
        new(name: config['name'], bridge_id: config['bridgeid'], model_id: config['modelid'],
            software_version: config['swversion'], api_version: config['apiversion'],
            time_zone: Client.get('/resource/bridge').first&.dig('time_zone', 'time_zone'),
            utc: config['UTC'], remote_access: config['portalservices'], analytics_consent: config['analyticsconsent'],
            http_blocked: config['httpblocked'])
      end

      # @return [Array<String>] the time zones the bridge accepts
      # @raise (see .read)
      # @api public
      def self.time_zones
        zones = ClipV1.object('capabilities').dig('timezones', 'values')
        zones || raise(ResponseError.new(200, ['no time zones in the answer']))
      end

      # Changes a setting the way the app does, a request for each. A setting written before a refusal stays written.
      #
      # @param time_zone [String, nil] one of {.time_zones}
      # @param utc [String, nil] the clock of the bridge
      # @param http_blocked [Boolean, nil] whether the bridge refuses plain HTTP
      # @param analytics_consent [Boolean, nil] whether the bridge may share statistics
      # @return [Settings] these settings with the values written, as the app keeps them; it reads only +http_blocked+
      #   back from the bridge, which is nil on a bridge that does not report it
      # @raise (see .read)
      # @api public
      def update(time_zone: nil, utc: nil, http_blocked: nil, analytics_consent: nil)
        written = { time_zone:, utc:, http_blocked:, analytics_consent: }.compact
        written.each { |name, value| ClipV1.request(:put, 'config', { WRITE.fetch(name) => value }) }
        written[:http_blocked] = http_blocked_read_back if written.key?(:http_blocked)
        with(**written)
      end

      # The requests of CLIP v1.
      module ClipV1
        UNAUTHORIZED = 1
        private_constant :UNAUTHORIZED

        # @param method [Symbol] +:get+ or +:put+
        # @param path [String] path under the application key
        # @param body [Hash, nil]
        # @return [Object] the JSON of the answer
        # @raise [AuthenticationError, ResponseError]
        # @api private
        def self.request(method, path, body = nil)
          key = Sdk.config.application_key or raise AuthenticationError, 'application_key is not configured'
          headers = body ? { 'Content-Type' => 'application/json' } : {} #: Hash[String, String]
          response = Connection.request(method, "/api/#{key}/#{path}", body: body && JSON.generate(body), headers:)
          status = response.code.to_i
          Client.instance.refuse(status, []) unless status == 200

          parse(response.body.to_s).tap { refuse(it) }
        end

        # @param path [String] path under the application key
        # @return [Hash{String=>Object}] the JSON object the bridge answers with
        # @raise [AuthenticationError, ResponseError]
        # @api private
        def self.object(path)
          answer = request(:get, path)
          answer.is_a?(Hash) ? answer : raise(ResponseError.new(200, ['the answer is not a JSON object']))
        end

        # @param body [String]
        # @return [Object]
        # @raise [ResponseError] if the body is not JSON
        # @api private
        def self.parse(body)
          JSON.parse(body)
        rescue JSON::ParserError
          raise ResponseError.new(200, ['the answer is not JSON'])
        end
        private_class_method :parse

        # CLIP v1 reports an error under a status 200: an object with +error+, or a list of them.
        #
        # @param answer [Object] the JSON of the answer
        # @return [void]
        # @raise [AuthenticationError, ResponseError]
        # @api private
        def self.refuse(answer)
          items = answer.is_a?(Array) ? answer : [answer]
          errors = items.filter_map { it['error'] if it.is_a?(Hash) }
          return if errors.empty?
          raise AuthenticationError, 'bridge rejected the application key' if errors.first['type'] == UNAUTHORIZED

          raise ResponseError.new(200, errors.map { it['description'].to_s })
        end
        private_class_method :refuse
      end
      private_constant :ClipV1

      private

      # The app reads this setting back in an action of its own, whose failure leaves what it held.
      #
      # @return [Boolean, nil]
      # @api private
      def http_blocked_read_back
        ClipV1.object('config')['httpblocked']
      rescue Error
        http_blocked
      end
    end
  end
end
