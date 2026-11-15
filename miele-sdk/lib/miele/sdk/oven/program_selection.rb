# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's oven module writes through PsSelectMessage (2/1577) once a program is selected: its
      # parameters, one by one.
      module ProgramSelection
        # +StartAt+ meaning now.
        NOW = 0xFFFF_FFFF_FFFF_FFFF
        # GLOBAL_PPHASE_STARTZEIT_LAEUFT: an automatic program counting down its delayed start.
        DELAYED_START = 28_002
        # InterpretAsDateTime reads a time of 0 or all ones as DateTime.MinValue, 0001-01-01.
        MIN_VALUE = Time.utc(1).to_i
        private_constant :NOW, :DELAYED_START, :MIN_VALUE

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

        # SetProgramStartTimeAction writes the start of a program that is not automatic, or of an automatic one
        # counting down its delayed start. It writes nothing otherwise: AutomaticProgramHelper keeps the start, with
        # the end the oven's minimums put after it, until {Requests#start} writes the start.
        #
        # @param time [Time, :now]
        # @param kept [AutomaticTimes, nil] the times the client keeps for this oven
        # @return [AutomaticTimes, nil] the times to keep from now on: +kept+ once the start is written, none for an
        #   automatic program to start now
        # @raise [ActionUnavailableError] on a Dop1 oven, or when 1/1574 lacks a value the app reads: nothing is sent
        # @api public
        def set_start_at(time, kept:)
          require_dop2!
          context = program_context
          return write_time(context, 13, unix_time(time), kept) unless keeps_times?(context)
          return unless time.is_a?(Time)

          AutomaticTimes.new(prog_id: selected_program(context), start_at: time, end_at: time + span(context))
        end

        # SetProgramEndTimeAction, as {#set_start_at}: an automatic program keeps the start the oven's minimums put
        # before the end.
        #
        # @param time [Time]
        # @param kept [AutomaticTimes, nil] the times the client keeps for this oven
        # @return [AutomaticTimes, nil] the times to keep from now on: +kept+ once the end is written; a minimum of 0
        #   or all ones counts from 0001-01-01, as the app reads it, which can give a start before 1970
        # @raise [ActionUnavailableError] on a Dop1 oven, or when 1/1574 lacks a value the app reads: nothing is sent
        # @api public
        def set_end_at(time, kept:)
          require_dop2!
          context = program_context
          return write_time(context, 14, unix_seconds(time), kept) unless keeps_times?(context)

          AutomaticTimes.new(prog_id: selected_program(context), start_at: time - span(context), end_at: time)
        end

        # The app moves the start to its minimum before a zero duration only (SetDurationAction).
        #
        # @param seconds [Integer]
        # @api public
        def duration=(seconds)
          require_dop2!
          within(Polling::ACTION_TIMEOUT) do
            context = seconds.zero? ? uncapped { start_reset } : program_context
            write_parameter(selected_program(context), 12, :u32, seconds)
          end
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
          return if options.empty?

          within(Polling::ACTION_TIMEOUT) do
            prog_id = selected_prog_id
            options.each { |id, on| write_parameter(prog_id, id, :bool, on) }
          end
        end

        private

        # @param id [Integer] its +GLOBAL_PS_SelectionParaCA+ attribute
        # @param type [Symbol] its wire type
        # @param value [Object]
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or when no program is selected: PsSelect has no ProgId to
        #   write
        # @raise [ArgumentError] for a value its wire type does not hold
        def set_parameter(id, type, value)
          within(Polling::ACTION_TIMEOUT) { write_parameter(selected_prog_id, id, type, value) }
        end

        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @param id [Integer] 13 for the start, 14 for the end
        # @param value [Integer] Unix seconds, all ones for now
        # @param kept [AutomaticTimes, nil]
        # @return [AutomaticTimes, nil] +kept+, which the app's write leaves alone
        # @raise [ActionUnavailableError] when no program is selected
        def write_time(context, id, value, kept)
          within(Polling::ACTION_TIMEOUT) { write_parameter(selected_program(context), id, :u64, value) }
          kept
        end

        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Boolean] whether the app keeps the times instead of writing them: an automatic program, but in
        #   phase 28002
        # @raise [ActionUnavailableError] without the program type, or an automatic program's phase
        def keeps_times?(context)
          attributes = context.prog_attributes_cca
          type = program_type(attributes) || raise(ActionUnavailableError, '1/1574 gives no program type')
          return false unless type == 3

          shown = phase(attributes) || raise(ActionUnavailableError, '1/1574 gives no phase')
          shown != DELAYED_START
        end

        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @return [Integer] seconds from the minimum start to the minimum end
        # @raise [ActionUnavailableError] when 1/1574 lacks either minimum
        def span(context)
          parameters = context.context_para_ca
          ends = parameters&.end_at&.min || raise(ActionUnavailableError, '1/1574 gives no minimum end')
          starts = parameters&.start_at&.min || raise(ActionUnavailableError, '1/1574 gives no minimum start')
          date_time(ends) - date_time(starts)
        end

        # InterpretAsDateTime, in Unix seconds.
        #
        # @param seconds [Integer]
        # @return [Integer]
        def date_time(seconds) = [0, NOW].include?(seconds) ? MIN_VALUE : seconds

        # SetDurationAction's ResetStartTimeAsync, which the app sends with its caller's token.
        #
        # @return [Objects::Oven::GlobalPsContext] 1/1574 as read before the start moves to its minimum
        # @raise [ActionUnavailableError] when no program is selected
        def start_reset
          context = program_context
          write_parameter(selected_program(context), 13, :u64, context.context_para_ca&.start_at&.min.to_i)
          context
        end

        # @return [Integer] the ProgId of the selected program on 1/1574
        # @raise [ActionUnavailableError] on a Dop1 oven, or when no program is selected
        def selected_prog_id
          require_dop2!
          selected_program(program_context)
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
          in Time then unix_seconds(time)
          end
        end

        # RawDataForDateTime stores ToUnixTimeSeconds' int64 in a uint64 (IL_000e): a time before 1970 wraps.
        #
        # @param time [Time]
        # @return [Integer]
        def unix_seconds(time) = time.to_i & NOW
      end
    end
  end
end
