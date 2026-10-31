# frozen_string_literal: true

module Miele
  module Sdk
    module Laundry
      # What the app's laundry module writes to select a program: 2/1577 on DOP2; on Dop1 the washer's 8201 or
      # the dryer's 8602, sent with the read request type. An Opcode appliance takes none.
      module Selection
        # @param prog_id [Integer, Symbol]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance
        # @raise [NotAcceptedError] when a Dop1 appliance refuses it
        # @api public
        def select_program(prog_id)
          require!(protocol_version == 2 || dop2?, 'the app selects no program on an Opcode appliance')
          return write_dop1_selection(dop1_selection(prog_id)) unless dop2?

          modify(Objects::Laundry::GlobalPsSelect, [2, 1577, 0, 0]) { it.with(prog_id:, selection_type: 0) }
        end

        private

        # The app accepts only Ack 1, characters 6 and 7 of the answer.
        #
        # @param section [Data] the washer's or the dryer's write section
        # @return [void]
        # @raise [NotAcceptedError] for any other Ack
        def write_dop1_selection(section)
          request = Dop1.request(object_id: dop1_objects.fetch(:write)::ID, type: Dop1::READ, section: section.to_bytes)
          ack = JSON.parse(dop1(request)).fetch('Response')[6, 2]
          raise NotAcceptedError, "the appliance answered Ack #{ack.inspect}" unless ack.to_i == 1
        end
      end
    end
  end
end
