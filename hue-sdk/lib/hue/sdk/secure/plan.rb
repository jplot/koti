# frozen_string_literal: true

require 'time'

module Hue
  module Sdk
    module Secure
      # The Hue Secure status of a device, as the app's +SubscriptionDeviceStatus+ gives it. Never tested on a device.
      module Plan
        TYPES = %w[camera tv bridge].freeze
        PAID = %w[hue.security.basic.single.monthly hue.security.basic.single.yearly hue.security.basic.dual.monthly
                  hue.security.basic.dual.yearly hue.security.plus.monthly hue.security.plus.yearly
                  hue.security.rfss.monthly hue.security.rfss.yearly].freeze
        STATES = %w[active grace_period future cancelled].freeze
        CAMERA = /\ACM[A-Z]\d{3}\z/
        BLOCKED = %i[free_tier experience_period_not_enabled].freeze
        ACTIONS = { subscribed: :run, experience_period: :inform_then_run, free_tier: :suggest_plan,
                    experience_period_not_enabled: :nothing, unknown: :refetch }.freeze
        GATED = %w[activity_zones package_detection_zones lighting_zones smoke_alarm_detection].freeze
        private_constant :TYPES, :PAID, :STATES, :CAMERA, :BLOCKED, :ACTIONS, :GATED

        # The plan's state (active, cancelled…) plays no part, as in the app: a device a plan lists is subscribed.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse, nil] as {Secure.subscription} reads it; nil when
        #   it could not be read
        # @param rid [String] a camera's or a bridge's id; a motion area takes its bridge's
        # @return [Symbol] +:subscribed+, +:experience_period+, +:free_tier+, +:experience_period_not_enabled+ or
        #   +:unknown+
        # @raise [ArgumentError] if the end of the experience period is not a date
        # @api public
        def self.status(details, rid)
          entry = details&.devices&.find { listed?(it) && it.rid.casecmp?(rid) }
          entry ? of(entry) : :unknown
        end

        # Whether the app's arming screen lets a motion area be picked for a mode, or taken out of it. It gives no
        # handler to an area whose bridge is free tier, and opens the plan offer; or has not started its trial, and
        # offers to start it ({.status} tells which). While the plans are not read, it disables every motion area.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse, nil] nil when the plans could not be read
        # @param bridge_id [String] the motion area's bridge
        # @return [Boolean]
        # @raise (see .status)
        # @api public
        def self.motion_area_selectable?(details, bridge_id)
          !details.nil? && !BLOCKED.include?(status(details, bridge_id))
        end

        # What the app does when a camera setting {.gated?} is changed: +:run+ for a subscribed camera;
        # +:inform_then_run+ in its trial, after a dialog; +:suggest_plan+, a dialog and no change, on the free tier;
        # +:nothing+ before its trial; +:refetch+, reading the plans again and no change, when its status is unknown.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse, nil] nil when the plans could not be read
        # @param camera_id [String]
        # @return [Symbol]
        # @raise (see .status)
        # @api public
        def self.camera_action(details, camera_id) = ACTIONS.fetch(status(details, camera_id))

        # Whether the app checks the camera's plan before this change ({.camera_action}): turning clip recording on,
        # the activity, package or lighting zones, sound detection. Turning clip recording off never is.
        #
        # @param request [Schema::CameraCameraServiceUpdate, Schema::CameraMicrophoneUpdate, Hash] as it would be sent
        # @param free_clips [Boolean] the app's remote setting +enable_24_hour_free_video_clips+ (off by default): when
        #   on, a free-tier camera records clips kept 24 hours, and the app no longer checks clip recording
        # @return [Boolean]
        # @raise [ArgumentError] if the request leaves a required field nil
        # @api public
        def self.gated?(request, free_clips:)
          body = JSON.parse(JSON.generate(request))
          (body['clips_recording'] == true && !free_clips) || GATED.any? { body.key?(it) }
        end

        # Whether the app's alarm devices screen lets the alarm pick what a camera of the home detects (people, pets,
        # vehicles), as its +hasSubscriptionOrExperiencePeriodWithMotionAreasInHome+ decides. Without, a camera offers
        # only common objects, and turning it off clears all four.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse, nil] nil when the plans could not be read
        # @param home [Home] as {Secure.homes} lists it, with its bridges and devices
        # @param motion_areas [Boolean] whether a bridge of the home has a motion area, as the bridge lists its
        #   +motion_area_configuration+ resources
        # @return [Boolean] true under a paid plan of the home in a state the app knows (active, grace_period, future,
        #   cancelled), while one of its cameras is in its trial, or one of its bridges with a motion area
        # @raise [ArgumentError] if the end of an experience period is not a date
        # @api public
        def self.covers?(details, home, motion_areas:)
          return false unless details

          paid?(details, home.id) || camera_trial?(details, home) || (motion_areas && bridge_trial?(details, home))
        end

        # @param entry [Schema::DeviceSubscriptionResponse]
        # @return [Symbol]
        # @api private
        def self.of(entry)
          return :subscribed if entry.subscription_ids.any?
          return :experience_period_not_enabled unless entry.xp_enabled
          return :unknown unless entry.xp_end_date

          Time.parse(entry.xp_end_date) < Time.now ? :free_tier : :experience_period
        end

        # @param details [Schema::AccountSubscriptionDetailsResponse]
        # @param home_id [String]
        # @return [Boolean]
        # @api private
        def self.paid?(details, home_id)
          details.subscriptions.any? do |plan|
            PAID.include?(plan.subscription_product.rid) && STATES.include?(plan.subscription_state) &&
              plan.homes.any? { it.rid == home_id }
          end
        end

        # @param details [Schema::AccountSubscriptionDetailsResponse]
        # @param home [Home]
        # @return [Boolean] whether a camera of the home, known by its product type, is in its trial
        # @api private
        def self.camera_trial?(details, home)
          home.devices.to_a.any? do |device|
            CAMERA.match?(device.type) && details.devices.any? { it.rid.casecmp?(device.id) && trial?(it) }
          end
        end

        # The app upper-cases a bridge's id as it reads the home, then compares it exactly.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse]
        # @param home [Home]
        # @return [Boolean] whether a bridge of the home is in its trial
        # @api private
        def self.bridge_trial?(details, home)
          home.bridges.to_a.any? { |id| details.devices.any? { it.rid == id.upcase && trial?(it) } }
        end

        # @param entry [Schema::DeviceSubscriptionResponse]
        # @return [Boolean]
        # @api private
        def self.trial?(entry) = listed?(entry) && of(entry) == :experience_period

        # @param entry [Schema::DeviceSubscriptionResponse]
        # @return [Boolean] whether the app keeps the entry in its list
        # @api private
        def self.listed?(entry) = TYPES.include?(entry.rtype) && (entry.rtype != 'tv' || entry.subscription_ids.any?)
        private_class_method :of, :paid?, :camera_trial?, :bridge_trial?, :trial?, :listed?
      end
    end
  end
end
