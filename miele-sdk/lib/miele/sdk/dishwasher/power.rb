# frozen_string_literal: true

module Miele
  module Sdk
    class Dishwasher < Appliance
      # Switching a DOP2 dishwasher on and off, and its delayed start, as the app's dishwasher module does.
      module Power
        COUNTDOWN_BITS = [1, 32, 33].freeze
        private_constant :COUNTDOWN_BITS

        # The app wakes a deep sleep first (+DeviceAction+ 2), then writes 2/1586 while +Status+ is 1 or 4; it
        # waits for the dishwasher between the steps, the SDK reads +State+ again.
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless it is off and under remote control
        # @api public
        def power_on
          require_dop2!
          state = self.state
          require!(off?(state) && state.remote_control?, 'the dishwasher cannot be switched on now')
          wake if standby(state) == 2
          return unless [1, 4].include?(status(self.state))

          modify(Objects::Dishwasher::GlobalDeviceCombiState, [2, 1586, 0, 0]) { it.with(appliance_state: 4) }
        end

        # @return [void]
        # @raise [ActionUnavailableError] unless it is on, under remote control and not locked
        # @api public
        def power_off
          require_dop2!
          state = self.state
          require!(!off?(state) && state.remote_control? && !locked_in?(state),
                   'the dishwasher cannot be switched off now')
          modify(Objects::Dishwasher::GlobalDeviceCombiState, [2, 1586, 0, 0]) { it.with(appliance_state: 1) }
        end

        # A DOP2 dishwasher that counts down (supported bits 1, 32 or 33) takes the minutes left, rounded up;
        # another takes the time as local seconds since 1970, as the app sends it, then request 8. A Dop1 one takes
        # the minutes on 8909, without a request.
        #
        # @param at [Time] its time of day; the next one if it has passed today
        # @return [void]
        # @raise [ActionUnavailableError] unless a program is selected (Status 3) under mobile start, as the app's
        #   ProgramStartFinishAtRule allows
        # @api public
        def start_delayed(at)
          require_start_time!
          now = Time.now
          return dop1_start_delayed(minutes_until(next_time(at, now), now)) unless dop2?

          bits = program_context.context_para_dw&.delayed_start_mode&.supported_bits.to_i
          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 1, 2]) { delayed(it, bits, next_time(at, now), now) }
          dop2_user_request(8)
        end

        private

        # @return [void]
        # @raise [ActionUnavailableError]
        def require_start_time!
          state = self.state
          require!(mobile?(state) && status(state) == 3, 'only a selected program takes a start time')
        end

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
