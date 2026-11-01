# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's oven module sends as user requests on 2/1583, for the main cavity only. A Dop1 oven only
      # stops, through +ProcessAction+.
      module Requests
        # The app writes each one the program requires and the user has not confirmed, with the value it shows
        # (SetRequiredParametersHelper).
        REQUIRED_PARAMETERS = { temperature: [6, :u16], core_temperature: [7, :u16], moisture: [2, :u8],
                                grill_level: [1, :u8], mw_power: [15, :u8], duration: [12, :u32],
                                browning: [30, :u8], doneness: [31, :u8] }.freeze
        # BuildProgramParameters hands these to TargetTemperature in degrees, which writes them back truncated: 3730
        # becomes 3729.
        TEMPERATURES = %i[temperature core_temperature].freeze
        PYROLYSIS_ABORTS = [324, 325].freeze
        private_constant :REQUIRED_PARAMETERS, :TEMPERATURES, :PYROLYSIS_ABORTS

        # An automatic program starts when its start time is written; the app sends no request for it.
        #
        # @param at [Time, :now] when an automatic program starts
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, with no program selected, or when the program requires a
        #   duration not set yet
        # @raise [ArgumentError] for a time given to a program that is not automatic, which takes +start_at=+
        # @api public
        def start(at: :now)
          require_dop2!
          context = program_context
          prog_id = selected_program(context)
          return start_automatic(prog_id, context, at) if automatic?(context)
          raise ArgumentError, 'only an automatic program starts at a given time; set start_at= first' if at != :now

          require_duration!(context)
          write_required_parameters(prog_id, context)
          write_dop2(Messages.user_request(supported_requests.include?(1) ? 1 : 113))
        end

        # @return [void]
        # @raise [ActionUnavailableError] when the oven offers no stop, or a DOP2 oven is not under remote control
        # @api public
        def stop
          return stop_dop1 unless dop2?

          state = self.state
          context = self.context
          requests = offered(context)
          require!(stoppable?(context, requests), 'the oven offers no stop now')
          require!(under_remote_control?(state), 'the oven stops only under remote control')
          write_dop2(Messages.user_request(stop_request(state, context, requests)))
        end

        # The app then raises the doneness or browning the oven asks for by one step, once the oven has moved on;
        # {ProgramSelection#doneness=} and {ProgramSelection#browning=} write it here.
        #
        # Offered while 1/1585 shows ContinueCooking 1 or 2, baking or cooking (ContinueProgramOptionRule).
        #
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or when not offered
        # @api public
        def continue_cooking = user_request(72, 'the oven offers no continue cooking now') { continue_cooking? }

        # Offered while 1/131 shows message 20 (OptionsRunningAfterEndRule).
        #
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or when the oven is not keeping warm
        # @api public
        def stop_keeping_warm = user_request(68, 'the oven is not keeping warm') { shows?(:message, 20) }

        private

        # @param id [Integer]
        # @param reason [String] why the oven does not offer it
        # @yieldreturn [Boolean] whether it does
        # @return [void]
        def user_request(id, reason)
          require_dop2!
          require!(yield, reason)
          write_dop2(Messages.user_request(id))
        end

        # @return [Boolean]
        def continue_cooking?
          type = context.prog_attributes_cca&.continue_cooking&.then { Objects::Oven::GlobalEnumContinueCookingTypes.to_i(it) }
          [1, 2].include?(type)
        end

        # @param context [Objects::Oven::GlobalPsContext]
        # @return [void]
        # @raise [ActionUnavailableError] when the duration is required but unset (0 or all ones)
        def require_duration!(context)
          duration = context.context_para_ca&.duration
          require!(!mask(duration).anybits?(2) || (1...0xFFFF_FFFF).cover?(duration&.current_value.to_i),
                   'the program requires a duration not set yet')
        end

        # @param prog_id [Integer]
        # @param context [Objects::Oven::GlobalPsContext]
        # @param at [Time, :now]
        # @return [void]
        def start_automatic(prog_id, context, at)
          write_required_parameters(prog_id, context)
          write_parameter(prog_id, 13, :u64, unix_time(at))
        end

        # @param context [Objects::Oven::GlobalPsContext]
        # @return [Boolean]
        def automatic?(context)
          context.prog_attributes_cca&.programtype&.then { Objects::Oven::GlobalEnumProgramTypes.to_i(it) } == 3
        end

        # @param prog_id [Integer]
        # @param context [Objects::Oven::GlobalPsContext]
        # @return [void]
        def write_required_parameters(prog_id, context)
          REQUIRED_PARAMETERS.each do |name, (id, type)|
            value = context.context_para_ca&.public_send(name)
            next unless unconfirmed?(name, value)

            current = value.current_value
            write_parameter(prog_id, id, type, TEMPERATURES.include?(name) ? hundredths(current / 100.0) : current)
          end
        end

        # As in the app, a duration out of its bounds stays unwritten.
        #
        # @param name [Symbol]
        # @param value [Object, nil] a +GLOBAL_GenericParameterValue+
        # @return [Boolean]
        def unconfirmed?(name, value)
          return false unless mask(value).anybits?(2) && mask(value).nobits?(4)

          name != :duration || value.current_value.to_i.between?(value.min.to_i, value.max.to_i)
        end

        # @param value [Object, nil] a +GLOBAL_GenericParameterValue+
        # @return [Integer] 1 writable, 2 required, 4 confirmed, 8 readable
        def mask(value) = value&.request_mask.to_i

        # @param context [Objects::Oven::GlobalDeviceContext]
        # @param requests [Array<Integer>]
        # @return [Boolean]
        def stoppable?(context, requests)
          prog_id = context.prog_attributes_cca&.prog_id
          aborting = prog_id && PYROLYSIS_ABORTS.include?(Objects::Oven::GlobalEnumPrgId.to_i(prog_id))
          !aborting && requests.intersect?([2, 55, 56, 57])
        end

        # DetermineStopRequestHelper: a sous-vide program (72) paused on info 198 stops with 2 even once started.
        #
        # @param state [State]
        # @param context [Objects::Oven::GlobalDeviceContext]
        # @param requests [Array<Integer>]
        # @return [Integer]
        def stop_request(state, context, requests)
          return 2 unless started?(state, context)
          return 2 if oven_state(state, context, requests) == :paused && state.program_id == 72 && shows?(:info, 198)

          [55, 56, 57].find { requests.include?(it) } || 2
        end

        # @param type [Symbol] +:info+, +:message+ or +:query+
        # @param ids [Array<Integer>]
        # @return [Boolean] whether 1/131 shows one of them
        def shows?(type, *ids)
          shown = notifications.then { { info: it.infos, message: it.messages, query: it.queries }.fetch(type) }
          Array(shown).any? { it.id && ids.include?(NOTIFICATION_IDS.fetch(type).to_i(it.id)) }
        end

        # The app's Dop1 rule asks for a program of raw type 0, 1 or 2 (function, own, automatic) and ignores
        # +RemoteEnable+.
        #
        # @return [void]
        def stop_dop1
          state = self.state
          require!(state.program_id.to_i.positive? && [0, 1, 2].include?(state.raw['ProgramType']),
                   'the oven runs no program')
          command(Schema::DeviceState.new(process_action: 2))
        end
      end
    end
  end
end
