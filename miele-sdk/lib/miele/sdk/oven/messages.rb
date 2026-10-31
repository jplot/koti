# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # The DOP2 messages the app's oven module builds attribute by attribute (Dop2WriteHelper), instead of
      # writing back what it read.
      module Messages
        # The NotificationAcknowledgeMessage attribute of each kind of notification.
        NOTIFICATIONS = { info: 1, message: 2, error: 3, query: 4 }.freeze

        module_function

        # PsSelectMessage, 2/1577: the attributes in the order the app appends them, 1, 3, then 2 and 7.
        #
        # @param prog_id [Integer]
        # @param selection_type [Integer] 0 selects the program, 2 sets one of its parameters
        # @param parameter [Array(Integer, Symbol, Object), nil] the id of a +GLOBAL_PS_SelectionParaCA+ attribute,
        #   its wire type and its value
        # @return [Dop2::Leaf]
        def ps_select(prog_id, selection_type, parameter = nil)
          fields = { 1 => Dop2::Field.new(type: :e16, value: prog_id), 3 => Dop2::Field.new(type: :e8, value: selection_type) }
          if parameter
            id, type, value = parameter
            fields[2] = Dop2::Field.new(type: :u16, value: id)
            fields[7] = Dop2::Field.new(type: :struct, value: { id => Dop2::Field.new(type:, value:) })
          end
          Dop2::Leaf.new(unit: 2, attribute: 1577, idx1: 0, idx2: 0, fields:)
        end

        # UserRequestMessage, 2/1583.
        #
        # @param id [Integer] a value of +GLOBAL_EnumUserRequestId+
        # @return [Dop2::Leaf]
        def user_request(id)
          Dop2::Leaf.new(unit: 2, attribute: 1583, idx1: 0, idx2: 0,
                         fields: { 1 => Dop2::Field.new(type: :e16, value: id) })
        end

        # NotificationAcknowledgeMessage: the app sets one of the four ids and sends the other three at 0.
        #
        # @param unit [Integer] 2, or 5 for a double oven's second cavity
        # @param type [Symbol] a key of {NOTIFICATIONS}
        # @param id [Integer]
        # @param option [Integer] a value of +GLOBAL_EnumNTFCTNAckOptions+
        # @return [Dop2::Leaf]
        def acknowledge(unit, type, id, option)
          ids = { 1 => 0, 2 => 0, 3 => 0, 4 => 0 }.merge(NOTIFICATIONS.fetch(type) => id)
          fields = ids.to_h { |index, value| [index, Dop2::Field.new(type: index == 3 ? :u32 : :e16, value:)] }
          Dop2::Leaf.new(unit:, attribute: 138, idx1: 0, idx2: 0,
                         fields: fields.merge(5 => Dop2::Field.new(type: :e8, value: option)))
        end
      end
    end
  end
end
