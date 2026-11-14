# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The arming of a home and its alarm, as the app's +ArmDisarmHttpClient+ reaches them. Never tested on a device.
      class Arm
        GEOFENCE = { nil => '', presence: '/presence', empty: '/empty' }.freeze
        BLOCKED = %i[free_tier experience_period_not_enabled].freeze
        DETECTIONS = %w[people pet vehicle].freeze
        private_constant :GEOFENCE, :BLOCKED, :DETECTIONS

        # @param home_id [String]
        # @api public
        def initialize(home_id)
          @home_id = home_id
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
        # +free_tier+ or +experience_period_not_enabled+, or while the plans cannot be read. It also refuses a camera's
        # people, pets or vehicles among what triggers the alarm unless {Plan.covers?} the home, and keeps the ones
        # already there. It reads the configuration first, then the plans, and the homes over gRPC, only as needed.
        #
        # @param request [Schema::ArmDisarmSetConfigRequest]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise [PlanError] if the change is one the app would not let through; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_config(request)
          sent = JSON.parse(JSON.generate(request))
          config = Secure.client.get("#{@path}/arm").body&.dig('config') || {}
          check_plans(moved(config, sent), picked(config, sent))
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

        # @param config [Hash{String=>Object}] the configuration now, as JSON
        # @param sent [Hash{String=>Object}] the request, as JSON
        # @return [Array<Hash{String=>Object}>] the motion areas the request lets into a mode or out of it
        # @api private
        def moved(config, sent)
          changes(config, sent, 'device', 'motion_area') { |before, after| gone(before, after) + gone(after, before) }
        end

        # @param config [Hash{String=>Object}] the configuration now, as JSON
        # @param sent [Hash{String=>Object}] the request, as JSON
        # @return [Array<Hash{String=>Object}>] the camera detections the request adds to a mode
        # @api private
        def picked(config, sent)
          changes(config, sent, 'alarm_triggering_entities', *DETECTIONS) { |before, after| gone(after, before) }
        end

        # The app knows an entry by its type and id; its bridge may come back empty, or in another case.
        #
        # @param from [Array<Hash{String=>Object}>]
        # @param to [Array<Hash{String=>Object}>]
        # @return [Array<Hash{String=>Object}>] the entries of +from+ that +to+ does not have
        # @api private
        def gone(from, to)
          from.reject { |entry| to.any? { it.values_at('type', 'id') == entry.values_at('type', 'id') } }
        end

        # @param config [Hash{String=>Object}] the configuration now, as JSON
        # @param sent [Hash{String=>Object}] the request, as JSON
        # @param key [String] the list to compare in each mode
        # @param types [Array<String>] the types of entry to compare
        # @yieldparam before [Array<Hash{String=>Object}>] the entries of a mode now
        # @yieldparam after [Array<Hash{String=>Object}>] the entries the request gives it
        # @yieldreturn [Array<Hash{String=>Object}>] those that change
        # @return [Array<Hash{String=>Object}>]
        # @api private
        def changes(config, sent, key, *types)
          %w[armed_stay armed_away].flat_map do |mode|
            yield entries(config[mode], key, types), entries(sent[mode], key, types)
          end
        end

        # @param mode [Hash{String=>Object}, nil]
        # @param key [String]
        # @param types [Array<String>]
        # @return [Array<Hash{String=>Object}>]
        # @api private
        def entries(mode, key, types)
          list = mode&.dig(key) || []
          list.select { types.include?(it['type']) }.map { it.slice('type', 'id', 'bridge') }
        end

        # @param moved [Array<Hash{String=>Object}>] motion areas in or out of a mode
        # @param picked [Array<Hash{String=>Object}>] camera detections new to a mode
        # @return [void]
        # @raise [PlanError]
        # @api private
        def check_plans(moved, picked)
          return if moved.empty? && picked.empty?

          details = Secure.subscription
          moved.each { check_area(details, it) }
          raise PlanError, @home_id unless picked.empty? || covered?(details)
        end

        # @param details [Schema::AccountSubscriptionDetailsResponse]
        # @param area [Hash{String=>Object}] a motion area in or out of a mode
        # @return [void]
        # @raise [ArgumentError] if it has no bridge, which the app always writes
        # @raise [PlanError]
        # @api private
        def check_area(details, area)
          raise ArgumentError, "motion area #{area['id']} has no bridge" unless area['bridge']

          status = Plan.status(details, area['bridge'])
          raise PlanError.new(area['bridge'], status) if BLOCKED.include?(status)
        end

        # A paid plan needs only the home's id; the homes are listed over gRPC, for their cameras and bridges, only
        # without one.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse]
        # @return [Boolean]
        # @api private
        def covered?(details)
          return true if Plan.covers?(details, Secure.home(@home_id))

          home = Secure.homes.find { it.id == @home_id }
          !home.nil? && Plan.covers?(details, home)
        end
      end
    end
  end
end
