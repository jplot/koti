# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The phones whose presence arms and disarms a home, as the app's +CloudGeofenceHttpClient+ reaches them. Never
      # tested on a device.
      class Geofence
        # @param home_id [String]
        # @api public
        def initialize(home_id)
          @path = "security/geofence-service/v1/home/#{home_id}/geofence/client"
        end

        # @return [Array<Schema::FetchGeofenceClientResponse>]
        # @raise (see Http.request)
        # @api public
        def list = Secure.client.get(@path).body.map { Schema::FetchGeofenceClientResponse.from(it) }

        # @param mobile_app_id [String] the phone
        # @param request [Schema::UpdateGeofenceClientRequest]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def create(mobile_app_id, request) = Secure.client.post("#{@path}/#{mobile_app_id}", body: request)

        # @param mobile_app_id [String] the phone
        # @param request [Schema::UpdateGeofenceClientRequest]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update(mobile_app_id, request) = Secure.client.put("#{@path}/#{mobile_app_id}", body: request)

        # @param mobile_app_id [String] the phone
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def delete(mobile_app_id) = Secure.client.delete("#{@path}/#{mobile_app_id}")

        # @param mobile_app_id [String] the phone
        # @param geofence_client_id [String] its client on one bridge
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def delete_bridge_client(mobile_app_id, geofence_client_id)
          Secure.client.delete("#{@path}/#{mobile_app_id}/bridge-client/#{geofence_client_id}")
        end
      end
    end
  end
end
