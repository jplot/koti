# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The arming of a home and its alarm, as the app's +ArmDisarmHttpClient+ reaches them. Never tested on a device.
      class Arm
        GEOFENCE = { nil => '', presence: '/presence', empty: '/empty' }.freeze
        private_constant :GEOFENCE

        # @param home_id [String]
        # @api public
        def initialize(home_id)
          @path = "security/arm-manager/v1/home/#{home_id}"
        end

        # @return [Schema::ArmDisarmResponse] the arm state and the configuration
        # @raise (see Http.request)
        # @api public
        def read = Schema::ArmDisarmResponse.from(Secure.client.get("#{@path}/arm").body)

        # @return [Schema::ArmDisarmStateResponse, nil] the arm state; nil for a home without Hue Secure, whose state
        #   the cloud gives as +null+
        # @raise (see Http.request)
        # @api public
        def state = Secure.client.get("#{@path}/arm/state").body&.then { Schema::ArmDisarmStateResponse.from(it) }

        # @param arm_state [String] +disarmed+, +armed_stay+ or +armed_away+
        # @param delay [Integer, nil] seconds before the state applies
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def set_state(arm_state, delay: nil)
          body = Schema::ArmDisarmSetStateRequest.new(arm_state:)
          Secure.client.put("#{@path}/arm/state", body:, query: delay ? { delay: } : {})
        end

        # @param request [Schema::ArmDisarmSetConfigRequest]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_config(request) = Secure.client.put("#{@path}/arm/config", body: request)

        # The app sends this one body to sound the alarm.
        #
        # @return [void]
        # @raise [ResponseError] with status 207 when part of the devices do not sound
        # @raise (see Http.request)
        # @api public
        def sound_alarm = Secure.client.put("#{@path}/alarm", body: { desired_state: 'alarming' })

        # @return [void]
        # @raise (see Http.request)
        # @api public
        def remove = Secure.client.delete("#{@path}/arm")

        # @param which [Symbol, nil] +:presence+ or +:empty+ for one of its two parts, nil for both
        # @return [void]
        # @raise [KeyError] for another part
        # @raise (see Http.request)
        # @api public
        def delete_geofence_config(which = nil)
          Secure.client.delete("#{@path}/arm/config/geofence#{GEOFENCE.fetch(which)}")
        end
      end
    end
  end
end
