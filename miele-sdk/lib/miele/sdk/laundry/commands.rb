# frozen_string_literal: true

module Miele
  module Sdk
    module Laundry
      # The actions of the app's laundry module, after the checks of its Mapping rules ({Rules}): on DOP2 each
      # object is read at 0/0, changed and written back with no index in the path; a Dop1 or Opcode appliance
      # takes +ProcessAction+ alone.
      module Commands
        WAKEABLE = { 1 => { 'R' => 0, 'V' => 0, 'D' => 5756, 'E' => 5801, 'G' => 5801, 'H' => 5801, 'I' => 5801 },
                     2 => { 'R' => 0, 'V' => 0 }, 24 => { 'R' => 0, 'W' => 0, 'D' => 5757 } }.freeze
        private_constant :WAKEABLE

        # {Rules#supported_requests} gives whether the app offers it: under remote control, the door locked.
        #
        # @return [void]
        # @api public
        def start = run_request(1)

        # @return [void]
        # @api public
        def stop = run_request(2)

        # A Dop1 appliance takes it as +ProcessAction+ 3, which the app never offers.
        #
        # @return [void]
        # @api public
        def pause = run_request(3)

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 or Opcode appliance, whose protocol has no 2/1583 to write
        # @api public
        def stop_end_signal
          require!(dop2?, 'only a DOP2 appliance has 2/1583 to stop its end signal')
          dop2_user_request(28)
        end

        # The app checks the requests 2/1585 lists, before its SupportedRequestsRule.
        #
        # @return [Boolean] whether the app offers {#stop_end_signal}: a DOP2 appliance listing request 28
        # @api public
        def stop_end_signal_offered? = dop2? && raw_requests(context).include?(28)

        # @return [void]
        # @api public
        def stop_to_edit = run_request(12_102)

        # The app shows it while the program waits for its start time (Status 4).
        #
        # @return [Boolean] whether the app offers {#stop_to_edit}: a program waiting, and request 12102 offered
        # @api public
        def stop_to_edit_offered?
          state = self.state
          status(state) == 4 && offered_requests(state, dop2? ? context : nil).include?(12_102)
        end

        # The app also stops offering it after three extensions in a row, which the SDK does not count;
        # {Rules#supported_requests} gives whether it offers request 12144.
        #
        # @return [void]
        # @api public
        def extend_anti_crease = run_request(12_144)

        # @return [Boolean] whether the app wakes the appliance: a DOP2 one of a series it wakes, sleeping deeply
        #   (Status 4, +StandbyState+ 2)
        # @api public
        def wake_offered?
          state = self.state
          dop2? && wakeable? && status(state) == 4 && state.raw['StandbyState'] == 2
        end

        # @param message [Integer, Symbol] the message shown
        # @param option [Integer, Symbol] one of its options
        # @return [void]
        # @api public
        def acknowledge(message:, option:)
          modify(Objects::Laundry::GlobalNtfctnAcknowledge, [2, 138, 0, 0]) { it.with(message:, ack_option: option) }
        end

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 or Opcode appliance, whose protocol has no 2/1586 to write
        # @api public
        def power_off
          require!(dop2?, 'only a DOP2 appliance has 2/1586 to switch off')
          modify(Objects::Laundry::GlobalDeviceCombiState, [2, 1586, 0, 0]) do |combi|
            combi.with(appliance_state: 1, operation_state: 0, process_state: 0)
          end
        end

        # @return [Boolean] whether the app offers {#power_off}: a DOP2 appliance showing its program done (Status 7)
        #   and its process state done or anti-crease (10 or 13), outside phases 264, 519 and 531
        # @api public
        def power_off_offered? = dop2? && finished?(state)

        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 or Opcode appliance
        # @api public
        def anti_crease=(value)
          require!(dop2?, 'only a DOP2 appliance takes its anti-crease setting from the app')
          modify(Objects::Laundry::GlobalSfValue, [2, 105, 12_037, 0]) { it.with(current_value: value) }
        end

        private

        # @param id [Integer]
        # @return [void]
        def run_request(id) = dop2? ? dop2_user_request(id) : command(Schema::DeviceState.new(process_action: id))

        # SupportsWakeup: the series letter at +TechType+[2], from a software id up on some.
        #
        # @return [Boolean]
        def wakeable?
          minimum = WAKEABLE.dig(identity.device_type, tech_type.to_s[2])
          !minimum.nil? && Array(identity.device_ident_label&.sw_ids).first.to_i >= minimum
        end

        # @param state [State]
        # @return [Boolean]
        def finished?(state)
          ![264, 519, 531].include?(state.raw['ProgramPhase'].to_i) && status(state) == 7 &&
            [10, 13].include?(process_state(context))
        end
      end
    end
  end
end
