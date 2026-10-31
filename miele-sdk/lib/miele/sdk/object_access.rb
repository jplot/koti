# frozen_string_literal: true

module Miele
  module Sdk
    # Reading and writing of the generated DOP2 objects at the addresses the app uses, for {Appliance}.
    module ObjectAccess
      # @param klass [Class] a generated DOP2 class, such as {Objects::Oven::GlobalPsSelect}
      # @param address [Array<Integer, nil>] one of +klass::ADDRESSES+ (default: the first), with the indexes the app
      #   computes given
      # @return [Data] an instance of +klass+
      # @raise [ArgumentError] when the address leaves an index to compute
      # @raise [Dop2::DecodeError]
      # @api public
      def object(klass, address = klass::ADDRESSES.first)
        unit, attribute, idx1, idx2 = settled(address)
        klass.from(dop2(unit, attribute, idx1:, idx2:).fields)
      end

      # The app writes some objects elsewhere than it reads them: the hood reads 2/426 at idx 0/0, writes it at 0/1.
      #
      # @param value [Data] a generated DOP2 value, read with {#object} then changed with +with+
      # @param address [Array<Integer, nil>] where the app writes it, from +ADDRESSES+
      # @param with_index [Boolean] as {Appliance#write_dop2} takes it
      # @return [void]
      # @raise [ArgumentError] when the address leaves an index to compute, or a changed member was not read
      # @api public
      def write_object(value, address, with_index: false)
        unit, attribute, idx1, idx2 = settled(address)
        write_dop2(Dop2::Leaf.new(unit:, attribute:, idx1: idx1.to_i, idx2: idx2.to_i, fields: value.to_fields),
                   with_index:)
      end

      # The app writes most objects back where it read them.
      #
      # @param klass [Class] a generated DOP2 class
      # @param address [Array<Integer, nil>] as {#object} takes it
      # @param with_index [Boolean] as {Appliance#write_dop2} takes it
      # @yieldparam value [Data] the object as read
      # @yieldreturn [Data] the object to write
      # @return [void]
      # @raise [ArgumentError] when a changed member was not read: nothing is written
      # @api public
      def modify(klass, address, with_index: false) = write_object(yield(object(klass, address)), address, with_index:)

      private

      # @param address [Array<Integer, nil>]
      # @return [Array<Integer, nil>]
      # @raise [ArgumentError] when it holds an index the app computes
      def settled(address)
        raise ArgumentError, "#{address.inspect}: give idx1 and idx2, which the app computes" if address.include?(nil)

        address #: [Integer, Integer, Integer?, Integer?]
      end
    end
  end
end
