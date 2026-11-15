# frozen_string_literal: true

module Miele
  module Sdk
    module Laundry
      # What the app's laundry module writes to select a program: 2/1577 on DOP2; on Dop1 the washer's 8201 or
      # the dryer's 8602, sent with the read request type. An Opcode appliance takes none.
      module Selection
        # @param prog_id [Integer, Symbol]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance, which has no selection object
        # @raise [NotAcceptedError] when a Dop1 appliance refuses it
        # @api public
        def select_program(prog_id)
          require_selection!
          return write_dop1_selection(dop1_selection(prog_id)) unless dop2?

          modify(Objects::Laundry::GlobalPsSelect, [2, 1577, 0, 0]) { it.with(prog_id:, selection_type: 0) }
        end

        private

        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode appliance
        def require_selection!
          require!(protocol_version == 2 || dop2?, 'an Opcode appliance has no selection object to write')
        end

        # The app sends it with the read request type.
        #
        # @param section [Data] the washer's or the dryer's write section
        # @return [void]
        # @raise [NotAcceptedError] when the appliance refuses it
        def write_dop1_selection(section)
          write_dop1_object(dop1_objects.fetch(:write), section, type: Dop1::READ, timeout: ATTEMPT_TIMEOUT)
        end

        # @return [Data] the washer's or the dryer's write section, which the app reads before it writes one
        def read_dop1_selection = dop1_object(dop1_objects.fetch(:write), timeout: ATTEMPT_TIMEOUT)
      end
    end
  end
end
