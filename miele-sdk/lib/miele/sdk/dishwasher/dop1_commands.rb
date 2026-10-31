# frozen_string_literal: true

module Miele
  module Sdk
    class Dishwasher < Appliance
      # What the app's dishwasher module sends a Dop1 dishwasher (protocol 2).
      module Dop1Commands
        EXTRA_BITS = { short: 0, eco: 1, dry: 2, intensive_low: 3, soak: 4, prerinse: 5, additional_drying: 6 }.freeze
        private_constant :EXTRA_BITS

        # @return [void]
        # @raise [ActionUnavailableError] on a DOP2 dishwasher, or unless it waits for its program (Status 2 or 3)
        #   under mobile start with the door closed (CanOpenDoorRule)
        # @api public
        def open_door
          require!(!dop2?, 'only a Dop1 dishwasher opens its door from the app')
          state = self.state
          require!(state.mobile_start? == true && [2, 3].include?(status(state)) && !state.door_open?,
                   'the dishwasher cannot open its door now')
          dop1(Dop1.request(object_id: '1404', type: Dop1::WRITE, section: [1, 2].pack('C2')))
        end

        private

        # The app writes back the whole +State+ it read, without its nulls, with the action.
        #
        # @param state [State]
        # @param action [Integer]
        # @return [void]
        def dop1_process_action(state, action)
          body = JSON.generate(state.raw.compact.merge('ProcessAction' => action))
          send_request(:put, "/Devices/#{fab}/State", body:)
        end

        # The app reads 8906 first and keeps the extras past bit 5.
        #
        # @param prog_id [Integer, Symbol]
        # @return [void]
        def dop1_select(prog_id)
          current = dop1_object(Objects::Dishwasher::SmartControlGsdProgrammwahlSetzen).bytes
          extras = current.byteslice(2, 2).to_s.ljust(2, "\0").unpack1('v') & ~0x3F
          write_selection(Objects::Dishwasher::SmartControlGsdProgrammIdEnum.to_i(prog_id), extras)
        end

        # The app takes the program from +State+, 3 when it shows none.
        #
        # @param selected [Array<Symbol>] keys of {EXTRA_BITS}
        # @return [void]
        def dop1_extras(selected)
          write_selection(state.raw['ProgramID'] || 3, selected.sum { 1 << EXTRA_BITS.fetch(it) })
        end

        # The app sends 8906 with the read request type.
        #
        # @param prog_id [Integer]
        # @param extras [Integer] the 16 extras bits
        # @return [void]
        def write_selection(prog_id, extras)
          dop1(Dop1.request(object_id: '8906', type: Dop1::READ, section: [1, prog_id, extras].pack('CCv')))
        end

        # @param minutes [Integer]
        # @return [void]
        def dop1_start_delayed(minutes)
          section = [1, minutes % 60, minutes / 60, 1].pack('C4')
          dop1(Dop1.request(object_id: '8909', type: Dop1::WRITE, section:))
        end
      end
    end
  end
end
