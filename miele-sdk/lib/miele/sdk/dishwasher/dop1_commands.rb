# frozen_string_literal: true

module Miele
  module Sdk
    class Dishwasher < Appliance
      # What the app's dishwasher module sends a Dop1 dishwasher (protocol 2).
      module Dop1Commands
        EXTRA_BITS = { short: 0, eco: 1, dry: 2, intensive_low: 3, soak: 4, prerinse: 5, additional_drying: 6 }.freeze
        private_constant :EXTRA_BITS

        # @return [void]
        # @raise [ActionUnavailableError] on a DOP2 dishwasher, whose protocol has no Dop1 object 1404
        # @api public
        def open_door
          require!(!dop2?, 'a DOP2 dishwasher has no Dop1 object 1404 to open its door')
          dop1(Dop1.request(object_id: '1404', type: Dop1::WRITE, section: [1, 2].pack('C2')), timeout: 5)
        end

        # CanOpenDoorRule.
        #
        # @return [Boolean] whether the app offers {#open_door}: a Dop1 dishwasher waiting for its program (Status 2
        #   or 3) under mobile start with the door closed
        # @api public
        def open_door_offered?
          return false if dop2?

          state = self.state
          state.mobile_start? == true && [2, 3].include?(status(state)) && !state.door_open?
        end

        private

        # The app writes back the +State+ it read as its DeviceStateDto, without nulls or keys it does not know.
        #
        # @param state [State]
        # @param action [Integer]
        # @return [void]
        def dop1_process_action(state, action)
          command(Schema::DeviceState.from(state.raw).with(process_action: action), timeout: 1)
        end

        # The app reads 8906 first and keeps the extras past bit 5.
        #
        # @param prog_id [Integer, Symbol]
        # @return [void]
        def dop1_select(prog_id)
          write_selection(Objects::Dishwasher::SmartControlGsdProgrammIdEnum.to_i(prog_id), extras_as_read(~0x3F))
        end

        # SelectExtrasForDop1Action keeps 8906's reserve bits as read; the program comes from +State+, 3 without one.
        #
        # @param selected [Array<Symbol>] keys of {EXTRA_BITS}
        # @return [void]
        # @raise [ArgumentError] for another name
        def dop1_extras(selected)
          bits = selected.sum { 1 << EXTRA_BITS.fetch(it) { raise ArgumentError, "8906 has no #{it} extra" } }
          reserve = extras_as_read(~0x7F)
          write_selection(state(timeout: 5).raw['ProgramID'] || 3, reserve | bits)
        end

        # @param kept [Integer] a mask of the 16 extras bits
        # @return [Integer] those bits as 8906 reads
        def extras_as_read(kept)
          current = dop1_object(Objects::Dishwasher::SmartControlGsdProgrammwahlSetzen, timeout: 5).bytes
          current.byteslice(2, 2).to_s.ljust(2, "\0").unpack1('v') & kept
        end

        # The app sends 8906 with the read request type.
        #
        # @param prog_id [Integer]
        # @param extras [Integer] the 16 extras bits
        # @return [void]
        def write_selection(prog_id, extras)
          dop1(Dop1.request(object_id: '8906', type: Dop1::READ, section: [1, prog_id, extras].pack('CCv')))
        end

        # SetStartTimeForDelayStartForDop1Action reads 8909 first, then overwrites all four fields: none goes back.
        #
        # @param at [Time] its time of day; the next one if it has passed
        # @return [void]
        def dop1_start_delayed(at)
          dop1_object(Objects::Dishwasher::SmartControlGsdStartTime, timeout: 5)
          now = Time.now
          minutes = minutes_until(next_time(at, now), now)
          section = [1, minutes % 60, minutes / 60, 1].pack('C4')
          dop1(Dop1.request(object_id: '8909', type: Dop1::WRITE, section:))
        end
      end
    end
  end
end
