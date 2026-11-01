# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's oven module writes through PsSelectMessage (2/1577) once a program is selected: its
      # parameters, one by one.
      module ProgramSelection
        # +StartAt+ meaning now.
        NOW = 0xFFFF_FFFF_FFFF_FFFF
        # The attributes whose section ShouldHideProgramParameters empties in the app: GrillLevelRule,
        # TargetMoistureRule, TargetTemperatureRule, TargetCoreTemperatureRule, MicrowaveLevelRule, SteamBurstsRule,
        # ProgramDurationRule, ProgramStartAtRule and ProgramEndAtRule.
        HIDDEN_WITH_PROGRAM = [1, 2, 6, 7, 8, 9, 10, 12, 13, 14, 15, 18].freeze
        private_constant :NOW, :HIDDEN_WITH_PROGRAM

        # @param celsius [Numeric]
        # @raise [ActionUnavailableError] see {#set_parameter}
        # @api public
        def target_temperature=(celsius)
          set_parameter(6, :u16, hundredths(celsius))
        end

        # @param celsius [Numeric] of the core probe
        # @api public
        def core_target_temperature=(celsius)
          set_parameter(7, :u16, hundredths(celsius))
        end

        # @param level [Integer]
        # @api public
        def moisture=(level)
          set_parameter(2, :u8, level)
        end

        # @param level [Integer]
        # @api public
        def grill_level=(level)
          set_parameter(1, :u8, level)
        end

        # @param level [Integer]
        # @api public
        def browning=(level)
          set_parameter(30, :u8, level)
        end

        # @param level [Integer]
        # @api public
        def doneness=(level)
          set_parameter(31, :u8, level)
        end

        # @param count [Integer]
        # @api public
        def steam_bursts=(count)
          set_parameter(18, :u8, count)
        end

        # The app 4.19.0 never enables its steam burst timer cells: UpdateSteamBurstPicker hands them
        # isUserAllowedToModifyFunctionParameters false.
        #
        # @param _seconds [Array<Integer>] up to three times, in seconds
        # @raise [ActionUnavailableError] always
        # @api public
        def steam_burst_times=(_seconds)
          raise ActionUnavailableError, 'the app never lets a steam burst time be set'
        end

        # @param time [Time, :now]
        # @api public
        def start_at=(time)
          set_parameter(13, :u64, unix_time(time))
        end

        # @param time [Time]
        # @api public
        def end_at=(time)
          set_parameter(14, :u64, time.to_i)
        end

        # The app moves the start to its minimum before a zero duration only (SetDurationAction).
        #
        # @param seconds [Integer]
        # @api public
        def duration=(seconds)
          context = program_context
          set_parameter(13, :u64, context.context_para_ca&.start_at&.min.to_i, context:) if seconds.zero?
          set_parameter(12, :u32, seconds, context:)
        end

        # Keep warm goes last, as in the app (WriteProgramOptionsAsync).
        #
        # @param rapid_heating [Boolean, nil]
        # @param pre_heating [Boolean, nil]
        # @param crisp [Boolean, nil]
        # @param rapid_cooling [Boolean, nil]
        # @param keep_warm [Boolean, nil]
        # @return [void]
        # @api public
        def set_options(rapid_heating: nil, pre_heating: nil, crisp: nil, rapid_cooling: nil, keep_warm: nil)
          options = { 21 => rapid_heating, 24 => pre_heating, 25 => crisp, 26 => rapid_cooling, 27 => keep_warm }
          options.each { |id, on| set_parameter(id, :bool, on) unless on.nil? }
        end

        private

        # @param id [Integer] a +GLOBAL_PS_SelectionParaCA+ attribute
        # @param type [Symbol] its wire type
        # @param value [Object]
        # @param context [Objects::Oven::GlobalPsContext, nil] 1/1574, read when not given
        # @return [void]
        # @raise [ActionUnavailableError]
        def set_parameter(id, type, value, context: nil)
          write_parameter(selected_program(shown_parameters(id, context)), id, type, value)
        end

        # @param id [Integer] a +GLOBAL_PS_SelectionParaCA+ attribute
        # @param context [Objects::Oven::GlobalPsContext, nil] 1/1574, read when not given
        # @return [Objects::Oven::GlobalPsContext] 1/1574
        # @raise [ActionUnavailableError] on a Dop1 oven, or when the app offers no such parameter now
        def shown_parameters(id, context = nil)
          require_dop2!
          device = require_parameters_allowed!
          selected = context || program_context
          shown = function_shown?(device.prog_attributes_cca, selected.prog_attributes_cca)
          require!(shown || !HIDDEN_WITH_PROGRAM.include?(id),
                   'the app hides this parameter while the oven shows no function, or 1/1574 another program')
          selected
        end

        # IsUserAllowedToModifyFunctionParametersRule: remote control and a program on the oven (1/1585), and
        # mobile start too once the program has started, or for program 361.
        #
        # @return [Objects::Oven::GlobalDeviceContext] 1/1585
        # @raise [ActionUnavailableError]
        def require_parameters_allowed!
          state = self.state
          device = context
          shown = device.prog_attributes_cca&.prog_id
          prog_id = shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown) : 0
          require!(under_remote_control?(state), 'the oven takes parameters only under remote control')
          require!(prog_id.positive?, 'the oven shows no program')
          if prog_id == 361 || started?(state, device)
            require!(state.mobile_start?, 'the oven takes parameters only by mobile start once a program has started')
          end
          device
        end

        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Integer] the ProgId of the selected program
        # @raise [ActionUnavailableError] when no program is selected
        def selected_program(context)
          prog_id = context.prog_attributes_cca&.prog_id || raise(ActionUnavailableError, 'no program is selected')
          Objects::Oven::GlobalEnumPrgId.to_i(prog_id)
        end

        # @param prog_id [Integer]
        # @param id [Integer] a +GLOBAL_PS_SelectionParaCA+ attribute
        # @param type [Symbol] its wire type
        # @param value [Object]
        # @return [void]
        def write_parameter(prog_id, id, type, value) = write_dop2(Messages.ps_select(prog_id, 2, [id, type, value]))

        # RawDataForTemperature: conv.u2 of the degrees times 100 truncates, 37.3 °C writing 3729.
        #
        # @param celsius [Numeric]
        # @return [Integer]
        def hundredths(celsius) = (celsius.to_f * 100).to_i

        # @param time [Time, :now]
        # @return [Integer] Unix seconds, all ones for now
        def unix_time(time)
          case time
          in :now then NOW
          in Time then time.to_i
          end
        end
      end
    end
  end
end
