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
        # @raise [ActionUnavailableError] see {#set_parameter}, or when the oven shows no microwave power
        # @raise [ArgumentError] for any other value
        # @raise [ResponseError] if the oven refuses it, but for a 500 followed by info 14 on 1/131 within 6 s
        # @api public
        def microwave_power=(bit)
          context = shown_parameters(15)
          supported = supported_powers(context)
          unless MICROWAVE_BITS.include?(bit) && supported.anybits?(bit)
            raise ArgumentError, "#{bit} is not one of the microwave power bits the oven supports (#{supported})"
          end

          write_microwave_power(selected_program(context), bit)
        end

        private

        # MicrowaveLevelRule gives the app no microwave section while MwPower is not readable.
        #
        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Integer] MwPower's SupportedBits
        # @raise [ActionUnavailableError]
        def supported_powers(context)
          power = context.context_para_ca&.mw_power
          return power.supported_bits.to_i if power && mask(power).anybits?(8)

          raise ActionUnavailableError, 'the oven shows no microwave power'
        end

        # SelectMicrowaveLevelAsync takes a 500 as done once 1/131 shows info 14, and rethrows it on any failure of
        # that wait.
        #
        # @param prog_id [Integer]
        # @param bit [Integer]
        # @return [void]
        # @raise [ResponseError]
        def write_microwave_power(prog_id, bit)
          write_parameter(prog_id, 15, :u8, bit)
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
