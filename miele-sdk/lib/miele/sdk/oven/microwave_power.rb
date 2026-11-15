# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's microwave section writes (MicrowaveLevelSectionViewModel, SelectMicrowaveLevelAction).
      module MicrowavePower
        # MicrowavePowers (80 to 1000 W) and MicrowaveSteps (1 to 7): the app's picker offers those of them set in
        # MwPower's SupportedBits, and writes the one picked.
        MICROWAVE_BITS = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40].freeze
        # The seconds SelectMicrowaveLevelAsync waits for info 14 after a 500.
        MICROWAVE_TIMEOUT = 6
        private_constant :MICROWAVE_BITS, :MICROWAVE_TIMEOUT

        # @param bit [Integer] one bit of the oven's supported microwave powers, such as 0x10 for 600 W
        # @raise [ActionUnavailableError] see {#set_parameter}
        # @raise [ArgumentError] for a value a byte does not hold
        # @raise [ResponseError] if the oven refuses it, but for a 500 followed by info 14 on 1/131 within 6 s
        # @api public
        def microwave_power=(bit)
          write_microwave_power(bit)
        end

        # @return [Array<Integer>] the bits the app's picker offers, those of MwPower's SupportedBits on 1/1574
        #   among the seven it knows
        # @api public
        def microwave_powers
          supported = program_context.context_para_ca&.mw_power&.supported_bits.to_i
          MICROWAVE_BITS.select { supported.anybits?(it) }
        end

        private

        # SelectMicrowaveLevelAsync takes a 500 as done once 1/131 shows info 14, and rethrows it on any failure of
        # that wait.
        #
        # @param bit [Integer]
        # @return [void]
        # @raise [ResponseError]
        def write_microwave_power(bit)
          set_parameter(15, :u8, bit)
        rescue ResponseError => e
          raise e unless e.status == 500 && power_message_shown?
        end

        # @return [Boolean, nil] whether 1/131 shows info 14 within the app's wait
        def power_message_shown?
          poll(MICROWAVE_TIMEOUT) { shows?(:info, 14) }
        rescue Error
          nil
        end
      end
    end
  end
end
