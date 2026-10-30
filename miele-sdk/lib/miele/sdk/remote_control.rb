# frozen_string_literal: true

module Miele
  module Sdk
    # Whether an appliance takes commands, read from its +RemoteEnable+ state as the Miele app reads it. The
    # including class gives +raw+, the +State+ resource, and +device_type+.
    module RemoteControl
      # How the Miele app reads +RemoteEnable+, by family: its oven, warming drawer and coffee modules compare
      # the first value, its dishwasher and laundry modules test bits. The others never read it.
      REMOTE_RULES = {
        oven: :equal, oven_microwave: :equal, steam_oven: :equal, steam_oven_combination: :equal,
        electrical_oven_double: :equal, steam_oven_microwave_combination: :equal, dish_warmer: :equal,
        coffee_system: :equal, dishwasher: :dishwasher, dishwasher_semi_professional: :dishwasher,
        washing_machine: :laundry, tumble_dryer: :laundry, washing_machine_semi_professional: :laundry,
        tumble_dryer_semi_professional: :laundry, washer_dryer: :laundry
      }.freeze
      private_constant :REMOTE_RULES

      # @return [Boolean, nil] whether the appliance accepts commands, nil for a family the app never asks
      # @api public
      def remote_control?
        case REMOTE_RULES[device_type]
        when :equal then [15, 7].include?(remote(0))
        when :dishwasher, :laundry then remote(0).anybits?(1)
        end
      end

      # @return [Boolean, nil] whether a program may be started from a phone, nil for a family the app never asks
      # @api public
      def mobile_start?
        case REMOTE_RULES[device_type]
        when :equal then remote(2) == 1
        when :dishwasher, :laundry then remote(2).anybits?(1)
        end
      end

      # @return [Boolean, nil] whether the appliance is being operated on its own panel, nil where the app never asks
      # @api public
      def local_control?
        case REMOTE_RULES[device_type]
        when :equal then remote(0) == 7
        when :laundry then remote(0).anybits?(8)
        end
      end

      private

      # @param index [Integer]
      # @return [Integer] that value of +RemoteEnable+, 0 when absent
      def remote(index) = raw.dig('RemoteEnable', index).to_i
    end
  end
end
