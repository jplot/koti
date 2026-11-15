# frozen_string_literal: true

module Miele
  module Sdk
    class Dishwasher < Appliance
      # Switching a DOP2 dishwasher on and off, and its delayed start, as the app's dishwasher module does.
      module Power
        COUNTDOWN_BITS = [1, 32, 33].freeze
        private_constant :COUNTDOWN_BITS

        # The app wakes a deep sleep first (+DeviceAction+ 2), then writes 2/1586 only while +State+ shows Status 1
        # or 4 (SwitchOnForDop2Action, IsApplianceStateDifferentThanOff under ExecuteSequentiallyUntilTrue); the SDK
        # reads +State+ again after the wake instead of waiting.
        #
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, whose protocol has no 2/1586 to write
        # @raise [ResponseError] when the appliance refuses DeviceAction 2, 400 included
        # @api public
        def power_on
          require_dop2!
          three_attempts { send_wake } if standby(state) == 2
          return unless [1, 4].include?(status(state))

          three_attempts do
            modify(Objects::Dishwasher::GlobalDeviceCombiState, [2, 1586, 0, 0]) { it.with(appliance_state: 4) }
          end
        end

        # @return [Boolean] whether the app offers {#power_on}: a DOP2 dishwasher off (Status 1, or 4 asleep) under
        #   remote control
        # @api public
        def power_on_offered?
          return false unless dop2?

          state = self.state
          off?(state) && state.remote_control? == true
        end

        # WakeUpForDop2Action: +DeviceAction+ 2 only while +State+ shows the dishwasher off (Status 1), or waiting to
        # start (Status 4) out of +StandbyState+ 1.
        #
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, which the app never wakes
        # @raise [ResponseError] when the dishwasher refuses it, 400 included
        # @api public
        def wake
          require!(dop2?, 'the app has no wake request for a Dop1 dishwasher')
          state = self.state
          send_wake if status(state) == 1 || (status(state) == 4 && standby(state) != 1)
        end

        # As SwitchOffForDop2Action (IsApplianceOffObservable), nothing goes out while +State+ shows Status 1.
        #
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, whose protocol has no 2/1586 to write
        # @api public
        def power_off
          require_dop2!
          return if status(state) == 1

          three_attempts do
            modify(Objects::Dishwasher::GlobalDeviceCombiState, [2, 1586, 0, 0]) { it.with(appliance_state: 1) }
          end
        end

        # @return [Boolean] whether the app offers {#power_off}: a DOP2 dishwasher on, under remote control and not
        #   locked
        # @api public
        def power_off_offered?
          return false unless dop2?

          state = self.state
          !off?(state) && state.remote_control? == true && !locked_in?(state)
        end

        # A DOP2 dishwasher that counts down (supported bits 1, 32 or 33) takes the minutes left, rounded up;
        # another takes the time as local seconds since 1970, as the app sends it, then request 8. A Dop1 one takes
        # the minutes on 8909, without a request.
        #
        # @param at [Time] its time of day; the next one if it has passed today
        # @return [void]
        # @api public
        def start_delayed(at)
          now = Time.now
          return dop1_start_delayed(minutes_until(next_time(at, now), now)) unless dop2?

          bits = program_context.context_para_dw&.delayed_start_mode&.supported_bits.to_i
          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 1, 2]) { delayed(it, bits, next_time(at, now), now) }
          dop2_user_request(8)
        end

        # @return [Boolean] whether the app's ProgramStartFinishAtRule offers {#start_delayed}: a program selected
        #   (Status 3) under mobile start
        # @api public
        def start_delayed_offered?
          state = self.state
          mobile?(state) && status(state) == 3
        end

        private

        # @param target [Time]
        # @param now [Time]
        # @return [Integer] wall-clock minutes, rounded up as the app's GetTimeOffsetToNow rounds them
        def minutes_until(target, now) = ((wall_clock(target) - wall_clock(now)) / 60).ceil

        # @param select [Data] 2/1577
        # @param bits [Integer] the supported start modes
        # @param target [Time]
        # @param now [Time]
        # @return [Data]
        def delayed(select, bits, target, now)
          para = select.selection_para_dw
          # SetStartTimeForDelayStartForDop2Action.SetParameter leaves the selection as read without a start mode.
          return select if para.nil? || bits.zero?

          mode, start = if COUNTDOWN_BITS.include?(bits)
                          [1, minutes_until(target, now)]
                        else
                          [2, wall_clock(target).to_i]
                        end
          select.with(selection_type: 2, selection_para_dw: para.with(delayed_start_mode: mode, delayed_start: start))
        end
      end
    end
  end
end
