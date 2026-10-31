# frozen_string_literal: true

module Miele
  module Sdk
    class Dishwasher < Appliance
      # The checks the app's dishwasher Mapping rules make before they enable an action, on +State+ (+Status+,
      # +StandbyState+, +SignalDoor+, +RemoteEnable+) and the first info of 2/131.
      module Rules
        STANDBY_STATES = [1, 2, 3].freeze
        private_constant :STANDBY_STATES

        private

        # @param state [State]
        # @return [Integer]
        def status(state) = state.raw['Status'].to_i

        # @param state [State]
        # @return [Integer] 1 on, 2 deep sleep, 3 light sleep, 255 for anything else
        def standby(state) = STANDBY_STATES.include?(state.raw['StandbyState']) ? state.raw['StandbyState'] : 255

        # @param state [State]
        # @return [Boolean]
        def locked_in?(state) = dop2? && state.raw['RemoteEnable']&.first == 7

        # @param state [State]
        # @return [Boolean] AppSupport bit 4, mobile start, and not locked
        def mobile?(state) = mobile_control? && state.mobile_start? == true && !locked_in?(state)

        # @param state [State]
        # @return [Boolean] Status 3, or 4 awake
        def ready?(state) = status(state) == 3 || (status(state) == 4 && [1, 255].include?(standby(state)))

        # @param state [State]
        # @return [Boolean] Status 1, or 4 asleep
        def off?(state) = status(state) == 1 || (status(state) == 4 && [2, 3].include?(standby(state)))

        # @param request [Symbol]
        # @return [Boolean]
        def offered?(request) = supported_requests.include?(request)

        # The app looks at the first info only.
        #
        # @return [void]
        # @raise [ActionUnavailableError] while it is info 700
        def require_no_info700!
          first = Array(notifications.infos).first&.id
          require!(first.nil? || Objects::Dishwasher::GlobalEnumNtfctnInfoId.to_i(first) != 700,
                   'the dishwasher shows info 700')
        end
      end
    end
  end
end
