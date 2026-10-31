# frozen_string_literal: true

module Miele
  module Sdk
    module Laundry
      # A delayed start as the app's laundry module sends it: on DOP2 2/1577 with the start and its mode, then
      # request 8; on Dop1 +StartTime+, the selection written back, then +ProcessAction+ 1.
      module DelayedStart
        MODES = [1, 32, 2, 8].freeze
        private_constant :MODES

        # @param at [Time] its time of day; the next one if it has passed today
        # @return [void]
        # @raise [ActionUnavailableError] unless the app offers start or request 8
        # @raise [NotAcceptedError] when a Dop1 appliance refuses its selection written back
        # @api public
        def start_delayed(at)
          now = Time.now
          target = next_time(at, now)
          require!(supported_requests.intersect?([1, 8]), 'the appliance cannot start later now')
          return dop1_start_delayed(target, now) unless dop2?

          write_dop2_selection { |para, source| delayed(para, source, target, now) }
          dop2_user_request(8)
        end

        private

        # GetTimeOffsetToNow counts from a minute ago: 90 minutes ahead gives 91.
        #
        # @param target [Time]
        # @param now [Time]
        # @return [Integer] whole minutes, 0 once passed
        def offset_minutes(target, now) = target < now ? 0 : ((wall_clock(target) - wall_clock(now) + 60) / 60).floor

        # The app takes the first of modes 1 and 32 (minutes), 2 and 8 (local seconds since 1970) the appliance
        # shows, current or supported; with none it leaves the start as copied.
        #
        # @param para [Data] the +selection_para+
        # @param source [Data] its counterpart in 2/1574
        # @param target [Time]
        # @param now [Time]
        # @return [Data]
        def delayed(para, source, target, now)
          shown = source.delayed_start_mode
          modes = shown ? shown.current_value.to_i | shown.supported_bits.to_i : 0
          mode = MODES.find { modes.anybits?(it) }
          return para unless mode

          start = [1, 32].include?(mode) ? offset_minutes(target, now) : wall_clock(target).to_i
          para.with(delayed_start_mode: mode, delayed_start: start)
        end

        # The app resets a +StartTime+ of 0 before it sets the hours and minutes.
        #
        # @param target [Time]
        # @param now [Time]
        # @return [void]
        def dop1_start_delayed(target, now)
          write_start_time(0, 0) if start_minutes(state).zero?
          minutes = offset_minutes(target, now)
          write_start_time(minutes / 60, minutes % 60)
          write_dop1_selection(dop1_parameters(dop1_object(dop1_objects.fetch(:write)), {}))
          command(Schema::DeviceState.new(process_action: 1))
        end

        # @param hours [Integer]
        # @param minutes [Integer]
        # @return [void]
        def write_start_time(hours, minutes) = command(Schema::DeviceState.new(start_time: [hours, minutes]))
      end
    end
  end
end
