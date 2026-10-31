# frozen_string_literal: true

module Miele
  module Sdk
    module Laundry
      # The laundry Mapping's SupportedRequestsRule, on +State+ (+Status+, +StandbyState+, +RemoteEnable+) and, on
      # DOP2, 2/1585 (the requests the appliance lists, its door and its process state).
      module Rules
        # @return [Array<Integer>] the user requests the app offers now: 1 start, 2 stop, 3 pause…
        # @api public
        def supported_requests = offered_requests(state, dop2? ? context : nil)

        private

        # @param state [State]
        # @return [Integer]
        def status(state) = state.raw['Status'].to_i

        # @param state [State]
        # @param context [Objects::Laundry::GlobalDeviceContext, nil] 2/1585 on DOP2
        # @return [Array<Integer>]
        def offered_requests(state, context)
          door, process, requests = request_inputs(state, context)
          return [] if (status(state) == 4 && state.raw['StandbyState'] == 2) || process == 6

          requests = without_unset_delay(allowed_by_state(requests, state))
          door == :locked && process != 15 ? requests : requests - [1]
        end

        # @param state [State]
        # @param context [Objects::Laundry::GlobalDeviceContext, nil]
        # @return [Array] the door, the process state (always 0 on Dop1) and the requests before the rule
        def request_inputs(state, context)
          return [dop1_door(state), 0, dop1_requests(state)] unless context

          [dop2_door(context), process_state(context), raw_requests(context)]
        end

        # @param requests [Array<Integer>]
        # @param state [State]
        # @return [Array<Integer>] only stop without remote control, no stop while a program waits (Status 2 or 3)
        def allowed_by_state(requests, state)
          requests &= [2] unless state.remote_control?
          [2, 3].include?(status(state)) ? requests - [2] : requests
        end

        # The app drops request 8 while the delayed-start mode 2/1574 shows is 0; a Dop1 appliance lists it only
        # with a start time.
        #
        # @param requests [Array<Integer>]
        # @return [Array<Integer>]
        def without_unset_delay(requests)
          return requests unless dop2? && requests.include?(8)

          mode = program_para(program_context)&.delayed_start_mode&.current_value
          mode.to_i.zero? ? requests - [8] : requests
        end

        # @param context [Objects::Laundry::GlobalDeviceContext]
        # @return [Array<Integer>] the requests 2/1585 lists
        def raw_requests(context)
          Array(context.supported_user_requests).map { Objects::Laundry::GlobalEnumUserRequestId.to_i(it) }
        end

        # @param context [Objects::Laundry::GlobalDeviceContext]
        # @return [Integer]
        def process_state(context)
          process = context.state&.process_state
          process.nil? ? 0 : Objects::Laundry::GlobalEnumProcessState.to_i(process)
        end

        # A Dop1 or Opcode appliance never offers pause.
        #
        # @param state [State]
        # @return [Array<Integer>]
        def dop1_requests(state)
          minutes = start_minutes(state)
          offered = { 1 => state.remote_control? && (status(state) == 4 || (programmed?(state) && minutes.zero?)),
                      2 => [4, 5].include?(status(state)), 8 => programmed?(state) && minutes.positive? }
          offered.filter_map { |request, on| request if on }
        end

        # @param state [State]
        # @return [Boolean] Status 3 under mobile start
        def programmed?(state) = status(state) == 3 && state.mobile_start? == true

        # @param state [State]
        # @return [Integer] +StartTime+ [h, m] in minutes, 0 without both
        def start_minutes(state)
          hours, minutes = state.raw['StartTime']
          hours && minutes ? (hours * 60) + minutes : 0
        end
      end
    end
  end
end
