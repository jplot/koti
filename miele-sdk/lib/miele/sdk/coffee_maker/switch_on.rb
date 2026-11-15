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
          within(TIMEOUT) do |since|
            return unless [1, 8, 255].include?(state.raw['Status'])

            3.times do |attempt|
              return send_switch_on(since)
            rescue Error
              raise if attempt == 2 || !paused?(since, 5)
            end
          end
        end

        # @param since [Numeric] when the switch-on began, on the appliance's monotonic clock
        # @return [void]
        # @raise [ActionFailedError] when the 45 s end within SwitchOnDelay, before the write
        def send_switch_on(since)
          leaf = switched_on(read_combi_state(since))
          return unless leaf
          raise ActionFailedError, "the coffee maker's switch-on ran past #{TIMEOUT} s" unless paused?(since, 1.5)

          write_dop2(leaf)
        end

        # @param since [Numeric]
        # @return [Dop2::Leaf] 2/1586 at 0/0, which SwitchOnHelper writes back as read
        def read_combi_state(since)
          dop2(2, 1586, idx1: 0, idx2: 0)
        rescue ResponseError => e
          raise unless e.status == 500

          rouse(since, e)
          retry
        end

        # HandleErrorDuringCombiStateRequest waits its 5 s beside the wake (Task.WhenAll): they go by even when the
        # wake fails, and the wake's own time counts in them.
        #
        # @param since [Numeric]
        # @param error [ResponseError] the 500, raised once the 45 s are up
        # @return [void]
        def rouse(since, error)
          started = @clock.call
          begin
            wake
          ensure
            pause = 5 - (@clock.call - started)
            raise error unless paused?(since, pause.positive? ? pause : 0)
          end
        end

        # @param since [Numeric]
        # @param seconds [Numeric]
        # @return [Boolean] whether the pause fits in the 45 s, waited then
        def paused?(since, seconds)
          return false if @clock.call - since + seconds >= TIMEOUT

          @sleeper.call(seconds) if seconds.positive?
          true
        end
      end
    end
  end
end
