# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's SelectOvenFunctionAction does: the program through PsSelectMessage (2/1577), then, once
      # 1/1574 shows it, the parameters it requires.
      module Selection
        # UnsupportedDop2Notifications.GenericQueryIds.
        UNSUPPORTED_QUERIES = [16_011, 16_013].freeze
        UNWRITABLE_STATES = %i[off not_connected running waiting_for_start].freeze
        private_constant :UNSUPPORTED_QUERIES, :UNWRITABLE_STATES

        # @param prog_id [Integer, Symbol] a value of +GLOBAL_EnumPrgId+
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or when the app's program selection is disabled; also once
        #   the program is selected, when 1/1574 lacks one of the eight parameters
        # @raise [ActionFailedError] when 1/1574 does not show the program within 15 s
        # @raise [Error] the first refusal of a required parameter, once every one is sent; the program stays selected
        # @api public
        def select_program(prog_id)
          require_dop2!
          require_program_writable!
          id = Objects::Oven::GlobalEnumPrgId.to_i(prog_id)
          write_dop2(Messages.ps_select(id, 0))
          write_required_parameters(id, shown_program_context(id))
        end

        private

        # DetermineIsProgramWriteable, which enables the app's program selection.
        #
        # @return [void]
        # @raise [ActionUnavailableError]
        def require_program_writable!
          state = self.state
          device = context
          require!(under_remote_control?(state), 'the oven selects a program only under remote control')
          require!(!UNWRITABLE_STATES.include?(oven_state(state, device, offered(device))),
                   'the oven is off, runs a program or waits to start one')
          require!(program_writeable?(device), 'the oven already shows a program')
          require!(!shows?(:query, *UNSUPPORTED_QUERIES), 'the oven asks a question the app cannot answer')
        end

        # IsProgramWriteable. Without a ProgId the app's entity fails, and its selection stays disabled.
        #
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def program_writeable?(device)
          shown = device.prog_attributes_cca&.prog_id
          shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown).zero? : false
        end

        # WaitForProgramToBeSet, under the app's timeout.
        #
        # @param id [Integer] the ProgId selected
        # @return [Objects::Oven::GlobalPsContext] 1/1574 showing it
        # @raise [ActionFailedError]
        def shown_program_context(id)
          poll(Polling::ACTION_TIMEOUT) { program_context.then { it if program_shown?(it, id) } } ||
            raise(ActionFailedError, "the oven did not show program #{id} within #{Polling::ACTION_TIMEOUT} s")
        end

        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @param id [Integer] the ProgId selected
        # @return [Boolean]
        def program_shown?(context, id)
          shown = context.prog_attributes_cca&.prog_id
          shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown) == id : false
        end
      end
    end
  end
end
