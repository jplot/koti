# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # The steam burst the app's oven module sends as user request 59 on 2/1583, offered as the app shows its
      # button (SteamBurstsSource, SteamBurstsRule).
      module SteamBurst
        STEAM_BURST_PARAMETERS = %i[number_of_steam_bursts start_burst_of_steam1 start_burst_of_steam2
                                    start_burst_of_steam3].freeze
        private_constant :STEAM_BURST_PARAMETERS

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or unless the oven offers request 59 for a REST ProgramID
        #   and a manual steam burst is left in a function that runs or pauses
        # @api public
        def steam_burst = user_request(59, 'the oven offers no steam burst now') { steam_burst? }

        private

        # SteamBurstsSource gives no entity without a REST ProgramID.
        #
        # @return [Boolean]
        def steam_burst?
          state = self.state
          device = context
          requests = offered(device)
          shown = device.prog_attributes_cca
          return false unless shown && state.program_id.to_i.positive? && requests.include?(59)

          manual_steam_burst?(shown) && %i[running paused].include?(oven_state(state, device, requests)) &&
            burst_left?(shown)
        end

        # SteamBurstsRule.Convert, on the entity ConvertToEntity builds only when every value it reads is there.
        #
        # @param shown [Objects::Oven::GlobalPsAttributesCCA] of 1/1585
        # @return [Boolean]
        def manual_steam_burst?(shown)
          selected = program_context
          parameters = STEAM_BURST_PARAMETERS.map { selected.context_para_ca&.public_send(it) }
          count = parameters.first
          parameters.all? { it&.request_mask && it.current_value } && mask(count).anybits?(8) &&
            [1, 2, 3].include?(count.current_value) && function_shown?(shown, selected.prog_attributes_cca)
        end

        # IsStartButtonVisible compares BitField to 16 as a whole, not as a bit.
        #
        # @param shown [Objects::Oven::GlobalPsAttributesCCA] of 1/1585
        # @return [Boolean]
        def burst_left?(shown)
          left = shown.remaining_steam_bursts&.then { it.current_value if it.request_mask }
          bit_field = shown.bit_field
          return false unless left && bit_field

          left.positive? || (left.zero? && bit_field == 16)
        end
      end
    end
  end
end
