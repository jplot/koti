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
        private_constant :TYPES, :PAID, :STATES, :CAMERA

        # The plan's state (active, cancelled…) plays no part, as in the app: a device a plan lists is subscribed.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse] as {Secure.subscription} reads it
        # @param rid [String] a camera's or a bridge's id; a motion area takes its bridge's
        # @return [Symbol] +:subscribed+, +:experience_period+, +:free_tier+, +:experience_period_not_enabled+ or
        #   +:unknown+
        # @raise [ArgumentError] if the end of the experience period is not a date
        # @api public
        def self.status(details, rid)
          entry = details.devices.find { listed?(it) && it.rid.casecmp?(rid) }
          entry ? of(entry) : :unknown
        end

        # Whether the app lets the alarm pick what a camera of the home detects (people, pets, vehicles), as its
        # +hasSubscriptionOrExperiencePeriodWithMotionAreasInHome+ decides. The app also wants a motion area on the
        # home's bridges before a bridge's trial counts; the cloud does not give motion areas, so the gem counts it.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse] as {Secure.subscription} reads it
        # @param home [Home] as {Secure.homes} lists it, with its bridges and devices
        # @return [Boolean] true under a paid plan of the home in a state the app knows (active, grace_period, future,
        #   cancelled), or while one of its cameras or bridges is in its trial
        # @raise [ArgumentError] if the end of an experience period is not a date
        # @api public
        def self.covers?(details, home)
          paid?(details, home.id) || camera_trial?(details, home) || bridge_trial?(details, home)
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
