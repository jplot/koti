# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # The app's OvenState, as far as a stop, a selection or a steam burst depends on it
      # (Sources.DOP2.OvenStateSource): a descaling (326) never pauses, and an info, a query or the open door holds
      # a program that cannot start.
      module OvenState
        INFO_QUERY_DOOR_PHASES = [10_001, 10_003, 28_116].freeze
        FUNCTIONAL_PROGRAM_TYPES = [2, 3, 4, 5, 7, 8, 38, 50].freeze
        APP_STATES = { off: :off, on: :on, waiting_to_start: :waiting_for_start, running: :running, pause: :paused,
                       end_programmed: :end, not_connected: :not_connected }.freeze
        STARTED = %i[waiting_for_start running paused end].freeze
        RUNNING = %i[waiting_for_start running paused].freeze
        # GLOBAL_PPHASE_PARA_CONSTRAINT, WARTEN_AUF_MANUELLENSTART and CONFIRM_START.
        STARTING_PHASES = [10_000, 28_004, 28_204].freeze
        private_constant :INFO_QUERY_DOOR_PHASES, :FUNCTIONAL_PROGRAM_TYPES, :APP_STATES, :STARTED, :RUNNING,
                         :STARTING_PHASES

        # ObserveProgramIsRunning, which StartProgramAction waits for within its 15 s; the SDK returns from
        # {Requests#start} once the oven takes the write, and the client reads what follows.
        #
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585, as {Oven#context} reads it
        # @param selected [Objects::Oven::GlobalPsContext] 1/1574, as {Oven#program_context} reads it
        # @return [Boolean] whether the oven shows a started program: waiting to start, running or paused, and 1/1574
        #   in a phase other than 10000, 28004 and 28204
        # @api public
        def program_running?(state, device, selected)
          shown = phase(selected.prog_attributes_cca)
          return false unless shown && RUNNING.include?(oven_state(state, device, offered(device)))

          !STARTING_PHASES.include?(shown)
        end

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
