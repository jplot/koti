# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # The app's OvenState, as far as a stop, a selection or a steam burst depends on it
      # (Sources.DOP2.OvenStateSource): a descaling (326) never pauses, and an info, a query or the open door holds
      # a program that cannot start. Its ShouldHideProgramParameters too.
      module OvenState
        INFO_QUERY_DOOR_PHASES = [10_001, 10_003, 28_116].freeze
        FUNCTIONAL_PROGRAM_TYPES = [2, 3, 4, 5, 7, 8, 38, 50].freeze
        APP_STATES = { off: :off, on: :on, waiting_to_start: :waiting_for_start, running: :running, pause: :paused,
                       end_programmed: :end, not_connected: :not_connected }.freeze
        STARTED = %i[waiting_for_start running paused end].freeze
        private_constant :INFO_QUERY_DOOR_PHASES, :FUNCTIONAL_PROGRAM_TYPES, :APP_STATES, :STARTED

        private

        # @param state [State]
        # @param context [Objects::Oven::GlobalDeviceContext]
        # @return [Boolean]
        def started?(state, context) = STARTED.include?(oven_state(state, context, offered(context)))

        # @param state [State]
        # @param context [Objects::Oven::GlobalDeviceContext]
        # @param requests [Array<Integer>]
        # @return [Symbol, nil]
        def oven_state(state, context, requests)
          base = state.program_id == 326 && state.status == :pause ? :running : APP_STATES[state.status]
          attributes = context.prog_attributes_cca
          phase = phase(attributes)
          startable = requests.include?(1)
          case base
          when :waiting_for_start then waiting_state(phase, startable)
          when :on then functional?(attributes) ? held_state(phase, startable) : base
          when :paused then held_state(phase, startable)
          else base
          end
        end

        # @param phase [Integer, nil]
        # @param startable [Boolean] whether the oven offers request 1
        # @return [Symbol]
        def waiting_state(phase, startable) = startable || phase == 10_000 ? :program_selected : :waiting_for_start

        # @param phase [Integer, nil]
        # @param startable [Boolean] whether the oven offers request 1
        # @return [Symbol]
        def held_state(phase, startable)
          INFO_QUERY_DOOR_PHASES.include?(phase) && !startable ? :paused : :program_selected
        end

        # @param attributes [Objects::Oven::GlobalPsAttributesCCA, nil]
        # @return [Integer, nil]
        def phase(attributes) = attributes&.prog_phase&.then { Objects::Oven::GlobalEnumPPhaseId.to_i(it) }

        # ShouldHideProgramParameters negated; its IsLoading is 1/1585 and 1/1574 showing different programs.
        #
        # @param shown [Objects::Oven::GlobalPsAttributesCCA, nil] of 1/1585
        # @param selected [Objects::Oven::GlobalPsAttributesCCA, nil] of 1/1574
        # @return [Boolean]
        def function_shown?(shown, selected)
          prog_id = shown&.prog_id
          return false unless prog_id && functional?(shown)

          Objects::Oven::GlobalEnumPrgId.to_i(prog_id).positive? && prog_id == selected&.prog_id
        end

        # @param attributes [Objects::Oven::GlobalPsAttributesCCA, nil]
        # @return [Boolean]
        def functional?(attributes)
          type = attributes&.programtype&.then { Objects::Oven::GlobalEnumProgramTypes.to_i(it) }
          FUNCTIONAL_PROGRAM_TYPES.include?(type)
        end
      end
    end
  end
end
