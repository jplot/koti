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
        private_constant :PARA_CONSTRAINT, :CONTINUED_PHASES

        # Offered while 1/1585 shows ContinueCooking 1 or 2, baking or cooking (ContinueProgramOptionRule).
        #
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or when not offered
        # @raise [ActionFailedError] when the oven does not cook on within the 15 s the app waits, or 1/1574 lacks
        #   the doneness or browning the app reads
        # @api public
        def continue_cooking
          user_request(72, 'the oven offers no continue cooking now') { continue_cooking? }
          phase, waited = timed_poll(Polling::ACTION_TIMEOUT) { shown_phase([PARA_CONSTRAINT, *CONTINUED_PHASES]) }
          waited += raise_cooking_level(Polling::ACTION_TIMEOUT - waited) if phase == PARA_CONSTRAINT
          continued, = timed_poll(Polling::ACTION_TIMEOUT - waited) { shown_phase(CONTINUED_PHASES) }
          raise ActionFailedError, "the oven did not cook on within #{Polling::ACTION_TIMEOUT} s" unless continued
        end

        private

        # @return [Boolean]
        def continue_cooking?
          type = context.prog_attributes_cca&.continue_cooking&.then { Objects::Oven::GlobalEnumContinueCookingTypes.to_i(it) }
          [1, 2].include?(type)
        end

        # @param phases [Array<Integer>]
        # @return [Integer, nil] the ProgPhase 1/1585 shows, when one of them
        def shown_phase(phases) = phase(context.prog_attributes_cca).then { it if phases.include?(it) }

        # SetRequiredCookingLevelAsync: it reads 1/1574 until it shows a level, then writes it one step higher.
        #
        # @param budget [Numeric] the seconds left of the app's wait
        # @return [Float] the seconds waited
        def raise_cooking_level(budget)
          found, waited = timed_poll(budget) do
            context = program_context
            required_cooking_level(context)&.then { [selected_program(context), *it] }
          end
          prog_id, id, level = found
          write_parameter(prog_id, id, :u8, level) if found
          waited
        end

        # DetermineCookingLevel: a doneness the oven requires and lets write, else such a browning. It reads both
        # with LeftOrThrow, so a missing one fails the action; conv.u1 wraps the step past 255 to 0.
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
