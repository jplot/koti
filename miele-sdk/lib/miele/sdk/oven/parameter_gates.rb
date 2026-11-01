# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # Whether the app's details page shows a program parameter: IsUserAllowedToModifyFunctionParametersRule for
      # every cell, and the Rules.ProgramParameters rule of each section.
      module ParameterGates
        MEMBERS = { temperature: :temperature, core_temperature: :core_temperature, moisture: :moisture,
                    grill_level: :grill_level, microwave_power: :mw_power, browning: :browning,
                    doneness: :doneness, steam_bursts: :number_of_steam_bursts, duration: :duration,
                    start_at: :start_at, end_at: :end_at }.freeze
        # BrowningLevelRule and DonenessLevelRule alone ignore ShouldHideProgramParameters.
        SHOWN_WITH_ANY_PROGRAM = %i[browning doneness].freeze
        OPTIONS = { 21 => :use_rapid_heating, 24 => :use_pre_heating, 25 => :use_crisp_function,
                    26 => :use_rapid_cooling, 27 => :use_holding }.freeze
        private_constant :MEMBERS, :SHOWN_WITH_ANY_PROGRAM, :OPTIONS

        private

        # @param name [Symbol] the parameter, as the setter names it
        # @return [Objects::Oven::GlobalPsContext] 1/1574
        # @raise [ActionUnavailableError] on a Dop1 oven, or unless the app shows the parameter
        def editable_parameters(name)
          state, device, selected = allowed_parameters
          require!(parameter_shown?(name, state, device, selected), "the app hides the #{name} now")
          selected
        end

        # ProgramOptionsRule lists the readable options of a function that 1/1585 and 1/1574 both show.
        #
        # @param ids [Array<Integer>] +GLOBAL_PS_SelectionParaCA+ attributes of options
        # @return [Objects::Oven::GlobalPsContext] 1/1574
        # @raise [ActionUnavailableError]
        def editable_options(ids)
          _state, device, selected = allowed_parameters
          options = ids.map { selected.context_para_ca&.public_send(OPTIONS.fetch(it)) }
          shown = function_shown?(device.prog_attributes_cca, selected.prog_attributes_cca)
          require!(shown && options.all? { readable?(it) }, 'the app hides these options now')
          selected
        end

        # @return [Array(State, Objects::Oven::GlobalDeviceContext, Objects::Oven::GlobalPsContext)]
        # @raise [ActionUnavailableError]
        def allowed_parameters
          require_dop2!
          state = self.state
          device = context
          require_parameters_allowed!(state, device)
          [state, device, program_context]
        end

        # IsUserAllowedToModifyFunctionParametersRule: remote control and a program on the oven (1/1585), and
        # mobile start too once the program has started, or for program 361.
        #
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [void]
        # @raise [ActionUnavailableError]
        def require_parameters_allowed!(state, device)
          shown = device.prog_attributes_cca&.prog_id
          prog_id = shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown) : 0
          require!(under_remote_control?(state), 'the oven takes parameters only under remote control')
          require!(prog_id.positive?, 'the oven shows no program')
          return unless prog_id == 361 || started?(state, device)

          require!(state.mobile_start?, 'the oven takes parameters only by mobile start once a program has started')
        end

        # An unreadable value empties every section, and ShouldHideProgramParameters all but two.
        #
        # @param name [Symbol]
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @param selected [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Boolean]
        def parameter_shown?(name, state, device, selected)
          parameters = selected.context_para_ca
          value = parameters&.public_send(MEMBERS.fetch(name))
          return false unless readable?(value)
          return false unless SHOWN_WITH_ANY_PROGRAM.include?(name) ||
                              function_shown?(device.prog_attributes_cca, selected.prog_attributes_cca)

          rule_shows?(name, value, parameters, %i[running paused].include?(oven_state(state, device, offered(device))))
        end

        # TargetTemperatureRule's IsInvalidTargetTemperature, and SteamBurstsRule with the steam burst type cell
        # (SteamBurstType 1 to 7).
        #
        # @param name [Symbol]
        # @param value [Object] the parameter's +GLOBAL_GenericParameterValue+
        # @param parameters [Objects::Oven::GlobalPsContextParaCA, nil]
        # @param running [Boolean] OvenState Running or Paused
        # @return [Boolean]
        def rule_shows?(name, value, parameters, running)
          case name
          when :temperature then value.current_value.to_i.positive?
          when :steam_bursts then (1..7).cover?(value.current_value)
          when :duration, :start_at, :end_at then time_shown?(name, value, parameters, running)
          else true
          end
        end

        # ProgramDurationRule, ProgramStartAtRule and ProgramEndAtRule.
        #
        # @param name [Symbol] +:duration+, +:start_at+ or +:end_at+
        # @param value [Object] the parameter's +GLOBAL_GenericParameterValue+
        # @param parameters [Objects::Oven::GlobalPsContextParaCA, nil]
        # @param running [Boolean] OvenState Running or Paused
        # @return [Boolean]
        def time_shown?(name, value, parameters, running)
          return !(running && duration_set?(value)) if name == :duration

          !(running && name == :start_at) && duration_allows?(parameters)
        end

        # @param parameters [Objects::Oven::GlobalPsContextParaCA, nil]
        # @return [Boolean] false while a readable duration is unset
        def duration_allows?(parameters)
          duration = parameters&.duration
          !readable?(duration) || duration_set?(duration)
        end

        # InterpretAsTimeSpan reads all ones as no duration.
        #
        # @param duration [Object] a +GLOBAL_GenericParameterValueU32+
        # @return [Boolean]
        def duration_set?(duration) = ![0, 0xFFFF_FFFF].include?(duration.current_value.to_i)

        # @param value [Object, nil] a +GLOBAL_GenericParameterValue+
        # @return [Boolean]
        def readable?(value) = mask(value).anybits?(8)
      end
    end
  end
end
