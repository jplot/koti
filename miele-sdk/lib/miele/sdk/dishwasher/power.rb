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
        # @raise [ActionUnavailableError] unless it is off, connected, and under remote control
        # @api public
        def power_on
          require_dop2!
          state = self.state
          require!(off?(state) && ![10, 255].include?(status(state)) && state.remote_control?,
                   'the dishwasher cannot be switched on now')
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

        # A dishwasher that counts down (supported bits 1, 32 or 33) takes the minutes left, rounded up; another
        # takes the time as local seconds since 1970, as the app sends it. Request 8 follows.
        #
        # @param at [Time] its time of day; the next one if it has passed today
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher
        # @api public
        def start_delayed(at)
          require_dop2!
          now = Time.now
          bits = program_context.context_para_dw&.delayed_start_mode&.supported_bits.to_i
          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 1, 2]) { delayed(it, bits, next_time(at, now), now) }
          dop2_user_request(8)
        end

        private

        # @param at [Time] a time of day
        # @param now [Time]
        # @return [Time] that time today, or tomorrow once it has passed, as GetTimeOffsetToNow takes it
        def next_time(at, now)
          target = Time.new(now.year, now.month, now.day) + (((at.hour * 60) + at.min) * 60)
          target < now ? target + 86_400 : target
        end

        # @param select [Data] 2/1577
        # @param bits [Integer] the supported start modes
        # @param target [Time]
        # @param now [Time]
        # @return [Data]
        def delayed(select, bits, target, now)
          para = select.selection_para_dw
          return select if para.nil? || bits.zero?

          mode, start = if COUNTDOWN_BITS.include?(bits)
                          [1, ((target - now) / 60.0).ceil]
                        else
                          [2, target.to_i + target.utc_offset]
                        end
          select.with(selection_type: 2, selection_para_dw: para.with(delayed_start_mode: mode, delayed_start: start))
        end
      end
    end
  end
end
