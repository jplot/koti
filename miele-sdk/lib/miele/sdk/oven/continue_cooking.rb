# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's ContinueProgramAction does with user request 72 on 2/1583: it waits for the oven to move on,
      # raises the doneness or browning the oven then asks for by one step, and waits for it to cook on.
      module ContinueCooking
        # ProgPhase ParaConstraint: the oven asks for a cooking level.
        PARA_CONSTRAINT = 10_000
        # ProgPhase heating and remaining time: the program goes on (ObserveProgramIsContinued).
        CONTINUED_PHASES = [28_100, 28_114, 28_115, 28_124].freeze
        # The raw programtype ConvertProgramType makes CleaningMaintenanceProgram.
        CLEANING_TYPE = 7
        private_constant :PARA_CONSTRAINT, :CONTINUED_PHASES, :CLEANING_TYPE

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, whose protocol has no 2/1583 to write
        # @raise [ActionFailedError] when the oven does not cook on within the 15 s the app waits, 1/1585 shows no
        #   program phase, or 1/1574 lacks the doneness, browning or ProgId the app reads
        # @api public
        def continue_cooking
          require_dop2!
          within(Polling::ACTION_TIMEOUT) do |since|
            write_dop2(Messages.user_request(72))
            phase = poll(Polling::ACTION_TIMEOUT, since:) { shown_phase([PARA_CONSTRAINT, *CONTINUED_PHASES]) }
            phase = nil if phase == PARA_CONSTRAINT && !cooking_level_raised?(since)
            continued = phase && poll(Polling::ACTION_TIMEOUT, since:) { shown_phase(CONTINUED_PHASES) }
            raise ActionFailedError, "the oven did not cook on within #{Polling::ACTION_TIMEOUT} s" unless continued
          end
        end

        # ProgramFinishedSpeechBubblesService, the only caller of the action: its continue bubble for ContinueCooking
        # 1 or 2 (ContinueProgramOptionRule) shows for a finished program while no option runs after the end, and
        # IsContinueButtonActive enables its button under RemoteEnableType MobileStart alone.
        #
        # @return [Boolean] whether the app offers {#continue_cooking}, never on a Dop1 oven
        # @api public
        def continue_cooking_offered?
          return false unless dop2?

          state = self.state
          device = context
          continue_cooking?(device) && program_finished?(state, device) && !option_running? &&
            under_remote_control?(state) == true && state.mobile_start? == true
        end

        private

        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def continue_cooking?(device)
          type = device.prog_attributes_cca&.continue_cooking&.then { Objects::Oven::GlobalEnumContinueCookingTypes.to_i(it) }
          [1, 2].include?(type)
        end

        # IsProgramInFinishedStateRule: OvenState End, and no cleaning or maintenance program.
        #
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def program_finished?(state, device)
          oven_state(state, device, offered(device)) == :end &&
            program_type(device.prog_attributes_cca) != CLEANING_TYPE
        end

        # The app reads ProgAttributesCCA and ProgPhase with LeftOrThrow, so a missing one fails the action.
        #
        # @param phases [Array<Integer>]
        # @return [Integer, nil] the ProgPhase 1/1585 shows, when one of them
        # @raise [ActionFailedError]
        def shown_phase(phases)
          shown = phase(context.prog_attributes_cca)
          raise ActionFailedError, '1/1585 shows no program phase' unless shown

          shown if phases.include?(shown)
        end

        # SetRequiredCookingLevelAsync: it reads 1/1574 until it shows a level, then writes it one step higher.
        #
        # @param since [Float] when the app's wait began, on the appliance's monotonic clock
        # @return [Boolean] whether 1/1574 showed a level within the wait, written then
        def cooking_level_raised?(since)
          found = poll(Polling::ACTION_TIMEOUT, since:) do
            context = program_context
            required_cooking_level(context)&.then { [written_program(context), *it] }
          end
          return false unless found

          prog_id, id, level = found
          write_parameter(prog_id, id, :u8, level)
          true
        end

        # Dop2WriteHelper.RetrieveProgramIdAsync reads the ProgId with LeftOrThrow, so a missing one fails the action.
        #
        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Integer]
        # @raise [ActionFailedError]
        def written_program(context)
          prog_id = context.prog_attributes_cca&.prog_id
          raise ActionFailedError, '1/1574 shows no ProgId' unless prog_id

          Objects::Oven::GlobalEnumPrgId.to_i(prog_id)
        end

        # DetermineCookingLevel: a doneness the oven requires and lets write, else such a browning. LeftOrThrow
        # fails the action on a missing doneness, or on a missing browning it goes on to read; conv.u1 wraps 256 to 0.
        #
        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Array(Integer, Integer), nil] the parameter's attribute and its value one step higher
        # @raise [ActionFailedError]
        def required_cooking_level(context)
          { doneness: 31, browning: 30 }.each do |name, id|
            value = context.context_para_ca&.public_send(name)
            raise ActionFailedError, "1/1574 has no #{name}" unless value&.request_mask && value.current_value

            return [id, (value.current_value + 1) & 0xFF] if mask(value).allbits?(3)
          end
          nil
        end
      end
    end
  end
end
