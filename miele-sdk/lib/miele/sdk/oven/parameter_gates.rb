# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # Whether the app's details page shows a program parameter and lets it change:
      # IsUserAllowedToModifyFunctionParametersRule for every cell, the Rules.ProgramParameters rule of each section,
      # and the section view model that enables its cell.
      module ParameterGates
        MEMBERS = { target_temperature: :temperature, core_target_temperature: :core_temperature, moisture: :moisture,
                    grill_level: :grill_level, microwave_power: :mw_power, browning: :browning,
                    doneness: :doneness, duration: :duration, start_at: :start_at, end_at: :end_at }.freeze
        # BrowningLevelRule and DonenessLevelRule alone ignore ShouldHideProgramParameters.
        SHOWN_WITH_ANY_PROGRAM = %i[browning doneness].freeze
        OPTIONS = { rapid_heating: :use_rapid_heating, pre_heating: :use_pre_heating, crisp: :use_crisp_function,
                    rapid_cooling: :use_rapid_cooling, keep_warm: :use_holding }.freeze
        # The raw programtypes ConvertProgramType makes Own or Automatic, and Automatic alone.
        FIXED_TIME_TYPES = [2, 3, 4].freeze
        AUTOMATIC_TYPES = [2, 3].freeze
        private_constant :MEMBERS, :SHOWN_WITH_ANY_PROGRAM, :OPTIONS, :FIXED_TIME_TYPES, :AUTOMATIC_TYPES

        # DetailParameterSectionViewModel and the temperature sections hide while IsOptionRunning holds.
        #
        # @param name [Symbol] a parameter as its setter names it: +:target_temperature+, +:core_target_temperature+,
        #   +:moisture+, +:grill_level+, +:microwave_power+, +:browning+, +:doneness+, +:duration+, +:start_at+ or
        #   +:end_at+ ({ProgramSelection#set_start_at}, {ProgramSelection#set_end_at})
        # @return [Boolean] whether the app's details page shows its section, never on a Dop1 oven
        # @raise [KeyError] for another name
        # @api public
        def parameter_shown?(name) = dop2? && !option_running? && section_shown?(name, state, context, program_context)

        # @param name [Symbol] a parameter, as {#parameter_shown?} names it
        # @return [Boolean] whether the app lets it change: its section shown, the parameters allowed
        #   (IsUserAllowedToModifyFunctionParametersRule) and its cell enabled
        # @raise [KeyError] for another name
        # @api public
        def parameter_editable?(name)
          return false unless dop2?

          state = self.state
          device = context
          selected = program_context
          value = selected.context_para_ca&.public_send(MEMBERS.fetch(name))
          parameters_allowed?(state, device) && !option_running? && section_shown?(name, state, device, selected) &&
            cell_enabled?(name, state, device, value)
        end

        # ProgramOptionsRule lists the readable options of a function that 1/1585 and 1/1574 both show.
        #
        # @param name [Symbol] +:rapid_heating+, +:pre_heating+, +:crisp+, +:rapid_cooling+ or +:keep_warm+, as
        #   {ProgramSelection#set_options} names it
        # @return [Boolean] whether the app shows the option, never on a Dop1 oven
        # @raise [KeyError] for another name
        # @api public
        def option_shown?(name) = dop2? && option_listed?(name, context, program_context)

        # @param name [Symbol] an option, as {#option_shown?} names it
        # @return [Boolean] whether the app lets it change: shown, the parameters allowed, the option writable and
        #   the options cell enabled
        # @raise [KeyError] for another name
        # @api public
        def option_editable?(name)
          return false unless dop2?

          state = self.state
          device = context
          selected = program_context
          value = selected.context_para_ca&.public_send(OPTIONS.fetch(name))
          parameters_allowed?(state, device) && option_listed?(name, device, selected) && writable?(value) &&
            options_cell_enabled?(state, device)
        end

        # TimeSource puts the times the app keeps on the start and end cells, in place of 1/1574's.
        #
        # @param kept [AutomaticTimes, nil] the times the client keeps for this oven
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585, as {Oven#context} reads it
        # @return [Boolean] whether the app's time cells show +kept+: 1/1585 shows an automatic program, its ProgId
        #   +kept+'s and above 0
        # @api public
        def kept_times_shown?(kept, device)
          attributes = device.prog_attributes_cca
          prog_id = attributes&.prog_id
          return false unless kept && prog_id && program_type(attributes) == 3

          shown = Objects::Oven::GlobalEnumPrgId.to_i(prog_id)
          shown.positive? && shown == kept.prog_id
        end

        private

        # IsOptionRunning: OptionsRunningAfterEndSource reads keep warm (message 20) or rapid cooling (19) on 1/131.
        #
        # @return [Boolean]
        def option_running? = shows?(:message, 20, 19)

        # @param name [Symbol]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @param selected [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Boolean]
        def option_listed?(name, device, selected)
          function_shown?(device.prog_attributes_cca, selected.prog_attributes_cca) &&
            readable?(selected.context_para_ca&.public_send(OPTIONS.fetch(name)))
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

        # IsUserAllowedToModifyFunctionParametersRule: remote control and a program on the oven (1/1585), and
        # mobile start too once the program has started, or for program 361.
        #
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def parameters_allowed?(state, device)
          shown = device.prog_attributes_cca&.prog_id
          prog_id = shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown) : 0
          return false unless under_remote_control?(state) == true && prog_id.positive?

          (prog_id != 361 && !started?(state, device)) || state.mobile_start? == true
        end

        # An unreadable value empties every section, and ShouldHideProgramParameters all but two.
        #
        # @param name [Symbol]
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @param selected [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Boolean]
        def section_shown?(name, state, device, selected)
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
          when :target_temperature then value.current_value.to_i.positive?
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

        # The section view models enable a cell for a writable value only; the cooking level cells need
        # RemoteEnableType MobileStart, and ReturnCorrectDuration and ReturnCorrectTimePoint make an own or automatic
        # program's times read-only without mobile start.
        #
        # @param name [Symbol]
        # @param state [State]
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @param value [Object, nil] the parameter's +GLOBAL_GenericParameterValue+
        # @return [Boolean]
        def cell_enabled?(name, state, device, value)
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
