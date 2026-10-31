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

        # The app sends it with the read request type.
        #
        # @param section [Data] the washer's or the dryer's write section
        # @return [void]
        # @raise [NotAcceptedError] when the appliance refuses it
        def write_dop1_selection(section) = write_dop1_object(dop1_objects.fetch(:write), section, type: Dop1::READ)
      end
    end
  end
end
