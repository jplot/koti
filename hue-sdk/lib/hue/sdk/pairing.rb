# frozen_string_literal: true

require 'json'

module Hue
  module Sdk
    # Obtains an application key from the bridge after its link button was
    # pressed. Nothing is persisted: storing the credentials is the caller's job.
    module Pairing
      # Keys returned by the bridge for a newly paired application.
      #
      # @!attribute [r] application_key
      #   @return [String] value for {Configuration::Settings#application_key}
      # @!attribute [r] client_key
      #   @return [String] value for {Configuration::Settings#client_key} (entertainment PSK, hex)
      Credentials = Data.define(:application_key, :client_key)

      LINK_BUTTON_NOT_PRESSED = 101
      private_constant :LINK_BUTTON_NOT_PRESSED

      module_function

      # Registers an application on the bridge.
      #
      # @param app_name [String] application name, at most 20 characters
      # @param instance_name [String] device name, truncated to 19 characters
      # @return [Credentials]
      # @raise [ArgumentError] if +app_name+ is longer than 20 characters
      # @raise [LinkButtonNotPressedError] if the link button was not pressed in the last 30 seconds
      # @raise [ResponseError] if the bridge refuses for another reason
      # @api public
      def pair(app_name:, instance_name:)
        raise ArgumentError, "app_name is limited to 20 characters: #{app_name}" if app_name.length > 20

        body = JSON.generate(devicetype: "#{app_name}##{instance_name[0, 19]}", generateclientkey: true)
        credentials(Connection.request(:post, '/api', body:, headers: { 'Content-Type' => 'application/json' }))
      end

      # @param response [Net::HTTPResponse]
      # @return [Credentials]
      # @api private
      def credentials(response)
        result = JSON.parse(response.body.to_s).first.to_h
        success = result['success']
        return Credentials.new(application_key: success['username'], client_key: success['clientkey']) if success

        refuse(response.code.to_i, result['error'].to_h)
      end

      # @param status [Integer] HTTP status of the answer
      # @param error [Hash{String=>Object}] the +error+ object of the answer
      # @return [void]
      # @raise [LinkButtonNotPressedError, ResponseError]
      # @api private
      def refuse(status, error)
        raise LinkButtonNotPressedError, error['description'] if error['type'] == LINK_BUTTON_NOT_PRESSED

        raise ResponseError.new(status, [error['description'].to_s])
      end
    end
  end
end
