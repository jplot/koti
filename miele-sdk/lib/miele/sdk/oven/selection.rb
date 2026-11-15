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

        # Once the program is selected, the client drops the times it keeps as {AutomaticTimes} says.
        #
        # @param prog_id [Integer, Symbol] a value of +GLOBAL_EnumPrgId+
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, whose protocol has no 2/1577 to write
        # @raise [ActionFailedError] when 1/1574 does not show the program within 15 s
        # @raise [RequiredParametersError] once 1/1574 shows the program, for the first refusal of a required
        #   parameter, once every one is sent, or for one of the eight missing from 1/1574; the program stays selected
        # @api public
        def select_program(prog_id)
          require_dop2!
          id = Objects::Oven::GlobalEnumPrgId.to_i(prog_id)
          context = within(Polling::ACTION_TIMEOUT) do |since|
            write_dop2(Messages.ps_select(id, 0))
            shown_program_context(id, since)
          end
          write_selected_parameters(id, context)
        end

        # DetermineIsProgramWriteable, which enables the app's program selection.
        #
        # @return [Boolean] whether the app offers {#select_program}: a DOP2 oven under remote control without local
        #   control, neither off nor running nor waiting to start, showing ProgId 0 on 1/1585, and asking neither
        #   query 16011 nor 16013
        # @api public
        def select_program_offered?
          return false unless dop2?

          state = self.state
          device = context
          writable = !UNWRITABLE_STATES.include?(oven_state(state, device, offered(device)))
          under_remote_control?(state) == true && writable && program_writeable?(device) &&
            !shows?(:query, *UNSUPPORTED_QUERIES)
        end

        private

        # The program is selected by then, and SelectOvenFunctionAsync has dropped what it keeps (IL_00dc).
        #
        # @param id [Integer]
        # @param context [Objects::Oven::GlobalPsContext]
        # @return [void]
        # @raise [RequiredParametersError] its cause the first refusal, or the parameter missing
        def write_selected_parameters(id, context)
          write_required_parameters(id, context)
        rescue Error => e
          raise RequiredParametersError, e.message
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
        # @param since [Float] when the action began, before its write
        # @return [Objects::Oven::GlobalPsContext] 1/1574 showing it
        # @raise [ActionFailedError]
        def shown_program_context(id, since)
          poll(Polling::ACTION_TIMEOUT, since:) { program_context.then { it if program_shown?(it, id) } } ||
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
