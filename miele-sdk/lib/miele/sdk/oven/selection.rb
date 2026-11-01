# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # What the app's SelectOvenFunctionAction does: the program through PsSelectMessage (2/1577), then, once
      # 1/1574 shows it, the parameters it requires.
      module Selection
        # The app's PollingDelay and ActionExecutionTimeout, in seconds, and the base of RetryOnRestException's
        # CalculateDelay: 1.5^n s before the n-th retry in a row.
        POLLING_DELAY = 3
        ACTION_TIMEOUT = 15
        RETRY_BASE = 1.5
        # UnsupportedDop2Notifications.GenericQueryIds.
        UNSUPPORTED_QUERIES = [16_011, 16_013].freeze
        UNWRITABLE_STATES = %i[off not_connected running waiting_for_start].freeze
        private_constant :POLLING_DELAY, :ACTION_TIMEOUT, :RETRY_BASE, :UNSUPPORTED_QUERIES, :UNWRITABLE_STATES

        # The app only logs a refused required parameter.
        #
        # @param prog_id [Integer, Symbol] a value of +GLOBAL_EnumPrgId+
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 oven, or when the app's program selection is disabled
        # @raise [ActionFailedError] when 1/1574 does not show the program within 15 s
        # @api public
        def select_program(prog_id)
          require_dop2!
          require_program_writable!
          id = Objects::Oven::GlobalEnumPrgId.to_i(prog_id)
          write_dop2(Messages.ps_select(id, 0))
          context = shown_program_context(id)
          begin
            write_required_parameters(id, context)
          rescue Error
            nil
          end
        end

        private

        # DetermineIsProgramWriteable, which enables the app's program selection.
        #
        # @return [void]
        # @raise [ActionUnavailableError]
        def require_program_writable!
          state = self.state
          device = context
          require!(under_remote_control?(state), 'the oven selects a program only under remote control')
          require!(!UNWRITABLE_STATES.include?(oven_state(state, device, offered(device))),
                   'the oven is off, runs a program or waits to start one')
          require!(program_writeable?(device), 'the oven already shows a program')
          require!(!shows?(:query, *UNSUPPORTED_QUERIES), 'the oven asks a question the app cannot answer')
        end

        # IsProgramWriteable. Without a ProgId the app's entity fails, and its selection stays disabled.
        #
        # @param device [Objects::Oven::GlobalDeviceContext] 1/1585
        # @return [Boolean]
        def program_writeable?(device)
          shown = device.prog_attributes_cca&.prog_id
          shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown).zero? : false
        end

        # WaitForProgramToBeSet, under the app's timeout.
        #
        # @param id [Integer] the ProgId selected
        # @return [Objects::Oven::GlobalPsContext] 1/1574 showing it
        # @raise [ActionFailedError]
        def shown_program_context(id)
          waited = 0.0
          failures = 0
          while waited < ACTION_TIMEOUT
            context = polled_program_context
            return context if context && program_shown?(context, id)

            failures = context ? 0 : failures + 1
            waited += pause(failures, waited)
          end
          raise ActionFailedError, "the oven did not show program #{id} within #{ACTION_TIMEOUT} s"
        end

        # RetryOnRestException ends the app's poll on a 4xx alone.
        #
        # @return [Objects::Oven::GlobalPsContext, nil] 1/1574, nil when a refusal is retried
        # @raise [ResponseError] for a 4xx
        def polled_program_context
          program_context
        rescue ResponseError => e
          raise if (400..499).cover?(e.status)
        end

        # @param context [Objects::Oven::GlobalPsContext] 1/1574
        # @param id [Integer] the ProgId selected
        # @return [Boolean]
        def program_shown?(context, id)
          shown = context.prog_attributes_cca&.prog_id
          shown ? Objects::Oven::GlobalEnumPrgId.to_i(shown) == id : false
        end

        # @param failures [Integer] the reads refused in a row
        # @param waited [Float] seconds since the selection
        # @return [Integer, Float] the seconds before the next read, slept unless past the app's timeout
        def pause(failures, waited)
          delay = failures.zero? ? POLLING_DELAY : RETRY_BASE**failures
          @sleeper.call(delay) if waited + delay < ACTION_TIMEOUT
          delay
        end
      end
    end
  end
end
