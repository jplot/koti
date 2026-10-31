# frozen_string_literal: true

module Miele
  module Sdk
    # An oven, steam oven or oven with microwave, which the Miele app's oven module handles (device types 12, 13,
    # 15, 31, 39 and 45).
    class Oven < Appliance
      # Switches the appliance on as the app's oven module does, waking it first when it sleeps. The app's
      # other families switch on in their own way.
      #
      # @return [void]
      # @raise [ResponseError] if the appliance still refuses after three attempts
      # @api public
      def power_on
        3.times do |attempt|
          rouse if attempt.positive?
          return write_dop2(power_leaf(4))
        rescue ResponseError => e
          raise unless e.status == 500 && attempt < 2
        end
      end

      # @return [void]
      # @raise [ResponseError] if the appliance refuses
      # @api public
      def power_off = write_dop2(power_leaf(1))

      private

      # The appliance state on 2/1586: 4 switches on, 1 off.
      #
      # @param state [Integer]
      # @return [Dop2::Leaf]
      def power_leaf(state)
        Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                       fields: { 1 => Dop2::Field.new(type: :e8, value: state) })
      end

      # A sleeping appliance answers 500 to the state write; the app then sends DeviceAction 2, waits 3 s and
      # tries again, with no limit: three attempts here.
      #
      # @return [void]
      def rouse
        begin
          wake
        rescue ResponseError
          nil
        end
        @sleeper.call(3)
      end
    end
  end
end
