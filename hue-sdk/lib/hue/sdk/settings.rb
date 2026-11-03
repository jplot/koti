# frozen_string_literal: true

require 'json'

module Hue
  module Sdk
    Settings = Data.define(:name, :bridge_id, :model_id, :software_version, :api_version, :time_zone, :utc,
                           :remote_access, :analytics_consent)

    # The settings of the bridge the Hue app reads and writes over CLIP v1, as CLIP v2 only reports the time zone.
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
    #   @return [Boolean, nil] whether the bridge may share statistics; the app sets it when pairing only
    class Settings
      WRITE = { time_zone: 'timezone', utc: 'UTC', http_blocked: 'blockhttp' }.freeze
      UNAUTHORIZED = 1
      private_constant :WRITE, :UNAUTHORIZED

      # Reads the settings of the bridge.
      #
      # @return [Settings]
      # @raise [AuthenticationError] if no application key is configured or the bridge rejects it
      # @raise [ResponseError] if the bridge refuses
      # @api public
      def self.read
        config = request(:get, 'config')
        new(name: config['name'], bridge_id: config['bridgeid'], model_id: config['modelid'],
            software_version: config['swversion'], api_version: config['apiversion'], time_zone: config['timezone'],
            utc: config['UTC'], remote_access: config['portalservices'], analytics_consent: config['analyticsconsent'])
      end

      # @return [Array<String>] the time zones the bridge accepts
      # @raise (see .read)
      # @api public
      def self.time_zones = request(:get, 'capabilities').dig('timezones', 'values').to_a

      # Changes a setting the way the app does, a request for each.
      #
      # @param time_zone [String, nil] one of {.time_zones}
      # @param utc [String, nil] the clock of the bridge
      # @param http_blocked [Boolean, nil] whether the bridge refuses plain HTTP
      # @return [Settings] the settings read again
      # @raise (see .read)
      # @api public
      def update(time_zone: nil, utc: nil, http_blocked: nil)
        { time_zone:, utc:, http_blocked: }.compact.each do |name, value|
          self.class.request(:put, 'config', { WRITE.fetch(name) => value })
        end
        self.class.read
      end

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
        raise ResponseError.new(response.code.to_i, []) unless response.code == '200'

        JSON.parse(response.body.to_s).tap { refuse(it) }
      end

      # CLIP v1 reports an error under a status 200, as a list.
      #
      # @param answer [Object] the JSON of the answer
      # @return [void]
      # @raise [AuthenticationError, ResponseError]
      # @api private
      def self.refuse(answer)
        errors = answer.is_a?(Array) ? answer.filter_map { it['error'] } : [] #: Array[Hash[String, untyped]]
        return if errors.empty?
        raise AuthenticationError, 'bridge rejected the application key' if errors.first['type'] == UNAUTHORIZED

        raise ResponseError.new(200, errors.map { it['description'].to_s })
      end
      private_class_method :refuse
    end
  end
end
