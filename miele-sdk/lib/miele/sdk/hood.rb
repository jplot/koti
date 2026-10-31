# frozen_string_literal: true

module Miele
  module Sdk
    # A cooker hood, which the Miele app's hood module handles (device type 18).
    class Hood < Appliance
      include Readings
      include Wire
      include Commands
      include Dop1Commands

      # @param pf_id [Integer] programming function id: 40010 and 40011 are the current grease and charcoal filter
      #   limits; writing 1 to 40012 or 40013 resets their operating hours
      # @return [Integer, nil] nil when the hood does not expose that setting
      # @api public
      def setting(pf_id) = Dop1.setting_value(JSON.parse(dop1(Dop1.setting(pf_id))).fetch('Response'))

      # @param pf_id [Integer] programming function id
      # @param value [Integer] unsigned 32-bit value
      # @return [void]
      # @raise [ArgumentError] if the id or the value is out of range
      # @api public
      def write_setting(pf_id, value) = tolerating_no_op { dop1(Dop1.write_setting(pf_id, value)) }
    end
  end
end
