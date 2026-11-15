# frozen_string_literal: true

module Miele
  module Sdk
    class CoffeeMaker < Appliance
      # A DOP2 coffee maker's switch-on as SwitchOnHelper`1 sends it under ExecuteSequentiallyUntilTrue: three
      # attempts, the next 5 s after a failure (RetryOnRestExceptionDelay), all within 45 s.
      module SwitchOn
        # SwitchOnActionTimeout, in seconds.
        TIMEOUT = 45
        private_constant :TIMEOUT

        private

        # Nothing goes out while +State+ shows it on, a Status other than 1, 8 and 255 or none (IsApplianceOn).
        #
        # @return [void]
        # @raise [Error] what fails the third attempt, or the 500 still answered once the 45 s are up
        def switch_on
          return unless [1, 8, 255].include?(state.raw['Status'])

          waits = [] #: Array[Integer | Float]
          3.times do |attempt|
            return send_switch_on(waits)
          rescue Error
            raise if attempt == 2 || !paused?(waits, 5)
          end
        end

        # @param waits [Array<Integer, Float>] the seconds this switch-on has waited
        # @return [void]
        def send_switch_on(waits)
          leaf = switched_on(read_combi_state(waits))
          return unless leaf

          @sleeper.call(1.5)
          waits << 1.5
          write_dop2(leaf)
        end

        # @param waits [Array<Integer, Float>]
        # @return [Dop2::Leaf] 2/1586 at 0/0, which SwitchOnHelper writes back as read
        def read_combi_state(waits)
          dop2(2, 1586, idx1: 0, idx2: 0)
        rescue ResponseError => e
          raise unless e.status == 500

          rouse(waits, e)
          retry
        end

        # HandleErrorDuringCombiStateRequest waits its 5 s beside the wake (Task.WhenAll): they go by even when the
        # wake fails.
        #
        # @param waits [Array<Integer, Float>]
        # @param error [ResponseError] the 500, raised once the 45 s are up
        # @return [void]
        def rouse(waits, error)
          wake
        ensure
          raise error unless paused?(waits, 5)
        end

        # @param waits [Array<Integer, Float>]
        # @param seconds [Integer]
        # @return [Boolean] whether the pause fits in the 45 s, waited then
        def paused?(waits, seconds)
          return false if waits.sum + seconds >= TIMEOUT

          @sleeper.call(seconds)
          waits << seconds
          true
        end
      end
    end
  end
end
