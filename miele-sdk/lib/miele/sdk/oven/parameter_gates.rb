# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # Whether the app's details page shows a program parameter and lets it change:
      # IsUserAllowedToModifyFunctionParametersRule for every cell, the Rules.ProgramParameters rule of each section,
      # and the section view model that enables its cell.
      module ParameterGates
        MEMBERS = { temperature: :temperature, core_temperature: :core_temperature, moisture: :moisture,
                    grill_level: :grill_level, microwave_power: :mw_power, browning: :browning,
                    doneness: :doneness, duration: :duration, start_at: :start_at, end_at: :end_at }.freeze
        # BrowningLevelRule and DonenessLevelRule alone ignore ShouldHideProgramParameters.
        SHOWN_WITH_ANY_PROGRAM = %i[browning doneness].freeze
        OPTIONS = { 21 => :use_rapid_heating, 24 => :use_pre_heating, 25 => :use_crisp_function,
                    26 => :use_rapid_cooling, 27 => :use_holding }.freeze
        # The raw programtypes ConvertProgramType makes Own or Automatic, and Automatic alone.
        FIXED_TIME_TYPES = [2, 3, 4].freeze
        AUTOMATIC_TYPES = [2, 3].freeze
        # Keep warm and rapid cooling (OptionsRunningAfterEndSource): DetailParameterSectionViewModel and the
        # temperature sections hide while 1/131 shows one.
        OPTION_RUNNING_MESSAGES = [20, 19].freeze
        private_constant :MEMBERS, :SHOWN_WITH_ANY_PROGRAM, :OPTIONS, :FIXED_TIME_TYPES, :AUTOMATIC_TYPES,
                         :OPTION_RUNNING_MESSAGES

        private

        # @param name [Symbol] the parameter, as the setter names it
        # @return [Objects::Oven::GlobalPsContext] 1/1574
        # @raise [ActionUnavailableError] on a Dop1 oven, or unless the app shows the parameter and lets it change
        def editable_parameters(name)
          state, device, selected = allowed_parameters
          require!(!shows?(:message, *OPTION_RUNNING_MESSAGES),
                   "the app hides the #{name} while keeping warm or rapid cooling")
          require!(parameter_shown?(name, state, device, selected), "the app hides the #{name} now")
          value = selected.context_para_ca&.public_send(MEMBERS.fetch(name))
          require!(parameter_editable?(name, state, device, value), "the app does not let the #{name} change now")
          selected
        end

        # ProgramOptionsRule lists the readable options of a function that 1/1585 and 1/1574 both show.
        #
        # @param ids [Array<Integer>] +GLOBAL_PS_SelectionParaCA+ attributes of options
        # @return [Objects::Oven::GlobalPsContext] 1/1574
        # @raise [ActionUnavailableError]
        def editable_options(ids)
          state, device, selected = allowed_parameters
          options = ids.map { selected.context_para_ca&.public_send(OPTIONS.fetch(it)) }
          shown = function_shown?(device.prog_attributes_cca, selected.prog_attributes_cca)
          require!(shown && options.all? { readable?(it) }, 'the app hides these options now')
          require!(options.all? { writable?(it) } && options_cell_enabled?(state, device),
                   'the app does not let these options change now')
          selected
        end

        # UpdateProgramOptionsIsEnabled: an automatic program's options need RemoteEnableType MobileStart or
        # LocalControl, mobile start once the user may change parameters.
        #
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def options_cell_enabled?(state, device)
          state.mobile_start? == true || !AUTOMATIC_TYPES.include?(program_type(device.prog_attributes_cca))
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

        # TargetTemperatureRule's IsInvalidTargetTemperature.
        #
        # @param name [Symbol]
        # @param value [Object] the parameter's +GLOBAL_GenericParameterValue+
        # @param parameters [Objects::Oven::GlobalPsContextParaCA, nil]
        # @param running [Boolean] OvenState Running or Paused
        # @return [Boolean]
        def rule_shows?(name, value, parameters, running)
          case name
          when :temperature then value.current_value.to_i.positive?
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

        # The section view models enable a cell for a writable value only; the cooking level cells need
        # RemoteEnableType MobileStart, and ReturnCorrectDuration and ReturnCorrectTimePoint make an own or automatic
        # program's times read-only without mobile start.
        #
        # @param name [Symbol]
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @param value [Object, nil] the parameter's +GLOBAL_GenericParameterValue+
        # @return [Boolean]
        def parameter_editable?(name, state, device, value)
          return false unless writable?(value)

          case name
          when :browning, :doneness then state.mobile_start? == true
          when :duration, :start_at, :end_at
            state.mobile_start? == true || !FIXED_TIME_TYPES.include?(program_type(device.prog_attributes_cca))
          else true
          end
        end

        # @param attributes [Objects::Oven::GlobalPsAttributesCCA, nil]
        # @return [Integer, nil] the raw programtype
        def program_type(attributes) = attributes&.programtype&.then { Objects::Oven::GlobalEnumProgramTypes.to_i(it) }

        # @param value [Object, nil] a +GLOBAL_GenericParameterValue+
        # @return [Boolean]
        def readable?(value) = mask(value).anybits?(8)

        # @param value [Object, nil] a +GLOBAL_GenericParameterValue+
        # @return [Boolean]
        def writable?(value) = mask(value).anybits?(1)
      end
    end
  end
end
