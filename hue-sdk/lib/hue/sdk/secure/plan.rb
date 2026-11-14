# frozen_string_literal: true

require 'time'

module Hue
  module Sdk
    module Secure
      # The app does not allow a change while a device has the Hue Secure status it has; nothing was sent.
      class PlanError < Error
        # @return [String] the device whose status the app checks
        attr_reader :rid

        # @return [Symbol] its status, as {Plan.status} gives it
        attr_reader :status

        # @param rid [String]
        # @param status [Symbol]
        # @api public
        def initialize(rid, status)
          @rid = rid
          @status = status
          super("the app does not allow this change while #{rid} is #{status}")
        end
      end

      # The Hue Secure status of a device, as the app's +SubscriptionDeviceStatus+ gives it. Never tested on a device.
      module Plan
        TYPES = %w[camera tv bridge].freeze
        private_constant :TYPES

        # The plan's state (active, cancelled…) plays no part, as in the app: a device a plan lists is subscribed.
        #
        # @param details [Schema::AccountSubscriptionDetailsResponse] as {Secure.subscription} reads it
        # @param rid [String] a camera's or a bridge's id; a motion area takes its bridge's
        # @return [Symbol] +:subscribed+, +:experience_period+, +:free_tier+, +:experience_period_not_enabled+ or
        #   +:unknown+
        # @raise [ArgumentError] if the end of the experience period is not ISO 8601
        # @api public
        def self.status(details, rid)
          device = details.devices.find { listed?(it) && it.rid.casecmp?(rid) }
          return :unknown unless device
          return :subscribed if device.subscription_ids.any?
          return :experience_period_not_enabled unless device.xp_enabled
          return :unknown unless device.xp_end_date

          Time.iso8601(device.xp_end_date) < Time.now ? :free_tier : :experience_period
        end

        # @param entry [Schema::DeviceSubscriptionResponse]
        # @return [Boolean] whether the app keeps the entry in its list
        # @api private
        def self.listed?(entry) = TYPES.include?(entry.rtype) && (entry.rtype != 'tv' || entry.subscription_ids.any?)
        private_class_method :listed?
      end
    end
  end
end
