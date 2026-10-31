# frozen_string_literal: true

module Miele
  module Sdk
    # Reading of +ExtendedState+ as the Miele app reads it, for {State}.
    module ExtendedState
      OVENS = %i[oven oven_microwave steam_oven steam_oven_combination electrical_oven_double
                 steam_oven_microwave_combination].freeze
      private_constant :OVENS

      # The Dop1 object the app builds from ExtendedState, by device type and ProtocolVersion: the zero bytes it puts
      # first, the bytes it skips (a Dop1 oven's first 3) and the byte order it gives. DOP2 hobs (4) are read through
      # DOP2 instead; the other families read their ExtendedState otherwise.
      EXTENDED_STATES = {
        [:hood, 1] => ['Hood::ExtendedOpCodeDeviceState', 0, 0, nil],
        [:hood, 2] => ['Hood::ExtendedDopDeviceState', 22, 0, nil],
        [:hood, 3] => ['Hood::ExtendedDop2DeviceState', 22, 0, nil],
        [:hood, 4] => ['Hood::ExtendedDop2DeviceState', 22, 0, nil],
        **%i[hob_highlight hob_induction hob_gas].product([1, 2])
                                                 .to_h { [it, ['Hob::ExtendedDeviceState', 22, 0, nil]] },
        **OVENS.to_h { [[it, 2], ['Oven::DeviceState::ZusatzinformationenDataSection', 0, 3, :msb]] }
      }.freeze
      private_constant :EXTENDED_STATES

      # @return [Data, nil] +ExtendedState+ as the app reads it, such as an {Objects::Hood::ExtendedDopDeviceState};
      #   nil for the families that read it otherwise, or when the appliance serves none
      # @api public
      def extended_state
        name, zeros, skipped, endian = EXTENDED_STATES[[device_type, protocol_version]]
        hex = raw['ExtendedState'].to_s
        return if name.nil? || hex.empty?

        klass = Objects.const_get(name)
        klass.from(("\0" * zeros) + [hex].pack('H*').byteslice(skipped..).to_s, endian: endian || klass::ENDIAN)
      end
    end
  end
end
