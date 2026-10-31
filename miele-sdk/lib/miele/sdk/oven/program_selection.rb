# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's oven module writes through PsSelectMessage (2/1577): the program, then its parameters one
      # by one.
      module ProgramSelection
        # +StartAt+ meaning now.
        NOW = 0xFFFF_FFFF_FFFF_FFFF
        private_constant :NOW

        # @param prog_id [Integer, Symbol] a value of +GLOBAL_EnumPrgId+
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or without remote control
        # @api public
        def select_program(prog_id)
          require_dop2!
          require!(under_remote_control?, 'the oven selects a program only under remote control')
          write_dop2(Messages.ps_select(Objects::Oven::GlobalEnumPrgId.to_i(prog_id), 0))
        end

        # @param celsius [Numeric]
        # @raise [ActionUnavailableError] see {#set_parameter}
        # @api public
        def target_temperature=(celsius)
          set_parameter(6, :u16, (celsius * 100).round)
        end

        # @param celsius [Numeric] of the core probe
        # @api public
        def core_target_temperature=(celsius)
          set_parameter(7, :u16, (celsius * 100).round)
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
        def microwave_power=(level)
          set_parameter(15, :u8, level)
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

        # @param seconds [Array<Integer>] up to three times, in seconds
        # @api public
        def steam_burst_times=(seconds)
          seconds.each_with_index { |time, index| set_parameter(8 + index, :u16, time) }
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

        # The app first moves the start to its minimum (SetDurationAction · ResetStartTimeAsync).
        #
        # @param seconds [Integer]
        # @api public
        def duration=(seconds)
          context = program_context
          set_parameter(13, :u64, context.context_para_ca&.start_at&.min.to_i, context:)
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
          require_dop2!
          require_parameters_allowed!
          write_parameter(selected_program(context || program_context), id, type, value)
        end

        # IsUserAllowedToModifyFunctionParametersRule: remote control and a program on the oven (1/1585), and
        # mobile start too once the program has started, or for program 361.
        #
        # @return [void]
        # @raise [ActionUnavailableError]
        def require_parameters_allowed!
          state = self.state
          device = context
          shown = device.prog_attributes_cca&.prog_id
          prog_id = shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown) : 0
          require!(under_remote_control?(state), 'the oven takes parameters only under remote control')
          require!(prog_id.positive?, 'the oven shows no program')
          return unless prog_id == 361 || started?(state, device)

          require!(state.mobile_start?, 'the oven takes parameters only by mobile start once a program has started')
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
