# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The arming of a home and its alarm, as the app's +ArmDisarmHttpClient+ reaches them. Never tested on a device.
      class Arm
        GEOFENCE = { nil => '', presence: '/presence', empty: '/empty' }.freeze
        BLOCKED = %i[free_tier experience_period_not_enabled].freeze
        private_constant :GEOFENCE, :BLOCKED

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

        # As the app does, it refuses to let a motion area into a mode or out of it while the area's bridge is
        # +free_tier+ or +experience_period_not_enabled+, or while the plans cannot be read. It reads the configuration
        # first, and the plans only when a motion area moves.
        #
        # @param request [Schema::ArmDisarmSetConfigRequest]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise [PlanError] if a motion area moves while the app would not let it; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_config(request)
          moved = moved_motion_areas(JSON.parse(JSON.generate(request)))
          check_plans(moved) unless moved.empty?
          Secure.client.put("#{@path}/arm/config", body: request)
        end

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

        private

        # @param sent [Hash{String=>Object}] the request as JSON
        # @return [Array<Hash{String=>Object}>] the motion areas it adds to a mode or removes from it
        # @api private
        def moved_motion_areas(sent)
          config = Secure.client.get("#{@path}/arm").body&.dig('config') || {}
          %w[armed_stay armed_away].flat_map do |mode|
            before = motion_areas(config[mode])
            after = motion_areas(sent[mode])
            (before - after) + (after - before)
          end
        end

        # @param mode [Hash{String=>Object}, nil]
        # @return [Array<Hash{String=>Object}>]
        # @api private
        def motion_areas(mode)
          devices = mode&.dig('device') || []
          devices.select { it['type'] == 'motion_area' }.map { it.slice('id', 'bridge') }
        end

        # @param areas [Array<Hash{String=>Object}>]
        # @return [void]
        # @raise [PlanError]
        # @api private
        def check_plans(areas)
          details = Secure.subscription
          areas.each do |area|
            status = Plan.status(details, area['bridge'])
            raise PlanError.new(area['bridge'], status) if BLOCKED.include?(status)
          end
        end
      end
    end
  end
end
