# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's oven module writes through PsSelectMessage (2/1577) once a program is selected: its
      # parameters, one by one.
      module ProgramSelection
        # +StartAt+ meaning now.
        NOW = 0xFFFF_FFFF_FFFF_FFFF
        private_constant :NOW

        # @param celsius [Numeric]
        # @raise [ActionUnavailableError] see {#set_parameter}
        # @api public
        def target_temperature=(celsius)
          set_parameter(:temperature, 6, :u16, hundredths(celsius))
        end

        # @param celsius [Numeric] of the core probe
        # @api public
        def core_target_temperature=(celsius)
          set_parameter(:core_temperature, 7, :u16, hundredths(celsius))
        end

        # @param level [Integer]
        # @api public
        def moisture=(level)
          set_parameter(:moisture, 2, :u8, level)
        end

        # @param level [Integer]
        # @api public
        def grill_level=(level)
          set_parameter(:grill_level, 1, :u8, level)
        end

        # @param level [Integer]
        # @api public
        def browning=(level)
          set_parameter(:browning, 30, :u8, level)
        end

        # @param level [Integer]
        # @api public
        def doneness=(level)
          set_parameter(:doneness, 31, :u8, level)
        end

        # @param count [Integer]
        # @api public
        def steam_bursts=(count)
          set_parameter(:steam_bursts, 18, :u8, count)
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
          set_parameter(:start_at, 13, :u64, unix_time(time))
        end

        # @param time [Time]
        # @api public
        def end_at=(time)
          set_parameter(:end_at, 14, :u64, time.to_i)
        end

        # The app moves the start to its minimum before a zero duration only (SetDurationAction).
        #
        # @param seconds [Integer]
        # @api public
        def duration=(seconds)
          context = editable_parameters(:duration)
          prog_id = selected_program(context)
          write_parameter(prog_id, 13, :u64, context.context_para_ca&.start_at&.min.to_i) if seconds.zero?
          write_parameter(prog_id, 12, :u32, seconds)
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
          options = options.compact
          prog_id = selected_program(editable_options(options.keys))
          options.each { |id, on| write_parameter(prog_id, id, :bool, on) }
        end

        private

        # @param name [Symbol] the parameter, as {ParameterGates} names it
        # @param id [Integer] its +GLOBAL_PS_SelectionParaCA+ attribute
        # @param type [Symbol] its wire type
        # @param value [Object]
        # @return [void]
        # @raise [ActionUnavailableError]
        def set_parameter(name, id, type, value)
          write_parameter(selected_program(editable_parameters(name)), id, type, value)
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
