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

        # @return [void]
        # @raise [ActionUnavailableError] unless the app offers request 1: under remote control, the door locked
        # @api public
        def start = run_request(1)

        # @return [void]
        # @raise [ActionUnavailableError] unless the app offers request 2
        # @api public
        def stop = run_request(2)

        # @return [void]
        # @raise [ActionUnavailableError] unless the app offers request 3, which a Dop1 appliance never does
        # @api public
        def pause = run_request(3)

        # The app checks the requests 2/1585 lists, before its SupportedRequestsRule.
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless a DOP2 appliance lists request 28
        # @api public
        def stop_end_signal
          require!(dop2? && raw_requests(context).include?(28), 'the appliance does not offer to stop its signal')
          dop2_user_request(28)
        end

        # The app shows it while the program waits for its start time (Status 4).
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless the program waits and the app offers request 12102
        # @api public
        def stop_to_edit
          require!(status(state) == 4, 'only a program waiting for its start time stops to be edited')
          run_request(12_102)
        end

        # The app also stops offering it after three extensions in a row, which the SDK does not count.
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless the app offers request 12144
        # @api public
        def extend_anti_crease = run_request(12_144)

        # @return [void]
        # @raise [ActionUnavailableError] unless a DOP2 appliance that the app wakes sleeps deeply (Status 4,
        #   +StandbyState+ 2)
        # @api public
        def wake
          state = self.state
          require!(dop2? && wakeable? && status(state) == 4 && state.raw['StandbyState'] == 2,
                   'the app does not wake this appliance now')
          super
        end

        # @param message [Integer, Symbol] the message shown
        # @param option [Integer, Symbol] one of its options
        # @return [void]
        # @api public
        def acknowledge(message:, option:)
          modify(Objects::Laundry::GlobalNtfctnAcknowledge, [2, 138, 0, 0]) { it.with(message:, ack_option: option) }
        end

        # @return [void]
        # @raise [ActionUnavailableError] unless a DOP2 appliance has finished its program (Status 7) or creases it
        #   (process state 10 or 13), outside phases 264, 519 and 531
        # @api public
        def power_off
          state = self.state
          require!(dop2? && finished?(state), 'the appliance cannot be switched off now')
          modify(Objects::Laundry::GlobalDeviceCombiState, [2, 1586, 0, 0]) do |combi|
            combi.with(appliance_state: 1, operation_state: 0, process_state: 0)
          end
        end

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
        # @raise [ActionUnavailableError] unless the app offers it
        def run_request(id)
          state = self.state
          require!(offered_requests(state, dop2? ? context : nil).include?(id), "request #{id} is not offered now")
          dop2? ? dop2_user_request(id) : command(Schema::DeviceState.new(process_action: id))
        end

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
