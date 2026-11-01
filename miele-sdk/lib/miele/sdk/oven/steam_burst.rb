# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # The steam burst the app's oven module sends as user request 59 on 2/1583, offered as the app shows its
      # button (SteamBurstsSource, SteamBurstsRule).
      module SteamBurst
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or unless the oven offers request 59 for a REST ProgramID
        #   and a manual steam burst is left in a function that runs or pauses
        # @api public
        def steam_burst = user_request(59, 'the oven offers no steam burst now') { steam_burst? }

        private

        # @return [Boolean]
        def steam_burst?
          state = self.state
          device = context
          state.program_id.to_i.positive? && offered(device).include?(59) && manual_steam_burst?(device) &&
            %i[running paused].include?(oven_state(state, device, offered(device))) &&
            burst_left?(device.prog_attributes_cca)
        end

        # NumberOfSteamBursts readable and Manual1 to Manual3, for a program the app does not hide
        # (ShouldHideProgramParameters).
        #
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def manual_steam_burst?(device)
          selected = program_context
          count = selected.context_para_ca&.number_of_steam_bursts
          mask(count).anybits?(8) && [1, 2, 3].include?(count&.current_value) &&
            function_shown?(device.prog_attributes_cca, selected.prog_attributes_cca)
        end

        # A function on 1/1585 that 1/1574 shows too: the app hides parameters while the two differ (IsLoading).
        #
        # @param shown [Objects::Oven::GlobalPsAttributesCCA, nil] of 1/1585
        # @param selected [Objects::Oven::GlobalPsAttributesCCA, nil] of 1/1574
        # @return [Boolean]
        def function_shown?(shown, selected)
          prog_id = shown&.prog_id
          return false unless prog_id && functional?(shown)

          Objects::Oven::GlobalEnumPrgId.to_i(prog_id).positive? && prog_id == selected&.prog_id
        end

        # IsStartButtonVisible: a burst left, or none left while the last one is under way (BitField equal to 16).
        #
        # @param shown [Objects::Oven::GlobalPsAttributesCCA, nil] of 1/1585
        # @return [Boolean]
        def burst_left?(shown)
          remaining = shown&.remaining_steam_bursts&.current_value
          return false unless remaining

          remaining.positive? || (remaining.zero? && shown&.bit_field == 16)
        end
      end
    end
  end
end
