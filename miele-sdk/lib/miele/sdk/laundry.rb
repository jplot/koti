# frozen_string_literal: true

module Miele
  module Sdk
    # What the app's laundry module reads from a washing machine, washer-dryer or tumble dryer.
    module Laundry
      include Rules
      include Commands
      include Selection
      include Parameters
      include DelayedStart

      # What a Dop1 laundry appliance reports of its program: its +ExtendedState+ past the first 3 bytes, and
      # +State+ for the temperature and spin speed.
      #
      # @!attribute [r] load
      #   @return [Integer]
      # @!attribute [r] soiling
      #   @return [Integer]
      # @!attribute [r] drying_level
      #   @return [Integer]
      # @!attribute [r] washing
      #   @return [Boolean]
      # @!attribute [r] drying
      #   @return [Boolean]
      # @!attribute [r] eco
      #   @return [Boolean]
      # @!attribute [r] energy
      #   @return [Integer] as the appliance counts it
      # @!attribute [r] water
      #   @return [Integer] as the appliance counts it
      # @!attribute [r] temperature
      #   @return [Integer] °C, 0 outside 0 to 100
      # @!attribute [r] spin_speed
      #   @return [Integer, nil] rpm
      Reading = Data.define(:load, :soiling, :drying_level, :washing, :drying, :eco, :energy, :water, :temperature,
                            :spin_speed)

      # @return [Objects::Laundry::GlobalDeviceContext] 2/1585, read without an index as the app reads it
      # @api public
      def context = object(Objects::Laundry::GlobalDeviceContext)

      # @return [Objects::Laundry::GlobalPsContext] 2/1574, idx 0/1
      # @api public
      def program_context = object(Objects::Laundry::GlobalPsContext)

      # @return [Objects::Laundry::GlobalNtfctnShow] 2/131, idx 0/1
      # @api public
      def notifications = object(Objects::Laundry::GlobalNtfctnShow)

      # @return [Objects::Laundry::GlobalSfValue] the anti-crease setting, 2/105 at idx1 12037
      # @api public
      def anti_crease = object(Objects::Laundry::GlobalSfValue)

      # The app reads 2/1584 at idx1 1, idx2 1 then (idx2 << 8) + 1 of the page before, while a page's indexes
      # differ (HasNext).
      #
      # @return [Array<Objects::Laundry::GlobalProgramList>]
      # @api public
      def programs
        pages = [] #: Array[untyped]
        idx2 = 1
        loop do
          leaf = dop2(2, 1584, idx1: 1, idx2:)
          pages << Objects::Laundry::GlobalProgramList.from(leaf.fields)
          return pages if leaf.idx1 == leaf.idx2

          idx2 = (leaf.idx2 << 8) + 1
        end
      end

      # @return [Symbol, Integer] +:open+, +:closed+, +:locked+, +:drying_plus+ or +:unknown+, a value the enum
      #   lacks as its number; a Dop1 or Opcode appliance reads +SignalDoor+, false being locked
      # @api public
      def door = dop2? ? dop2_door(context) : dop1_door(state)

      # @return [Reading, nil] nil off Dop1, or without +ExtendedState+
      # @api public
      def readings
        return unless protocol_version == 2

        state = self.state
        bytes = [state.raw['ExtendedState'].to_s].pack('H*').byteslice(3..).to_s
        reading(bytes, state) if bytes.bytesize >= 64
      end

      # @return [Data] Dop1 object 8200 on a washer, 8600 on a dryer
      # @api public
      def program_list = dop1_object(dop1_objects.fetch(:list))

      # @return [Data] Dop1 object 8202 on a washer, 8601 on a dryer
      # @api public
      def selection = dop1_object(dop1_objects.fetch(:selection))

      private

      # @return [Boolean]
      def dop2? = [3, 4].include?(protocol_version)

      # @return [Boolean]
      def dryer? = is_a?(TumbleDryer)

      # @param context [Objects::Laundry::GlobalPsContext] 2/1574
      # @return [Data, nil] the dryer's parameters, or the washer's and the washer-dryer's
      def program_para(context) = dryer? ? context.context_para_td : context.context_para_wm

      # @param context [Objects::Laundry::GlobalDeviceContext]
      # @return [Symbol, Integer]
      def dop2_door(context)
        door = context.device_attributes_dwtdwm&.door_state || :unknown
        door == :closed && dryer? ? :locked : door
      end

      # @param state [State]
      # @return [Symbol]
      def dop1_door(state) = { true => :open, false => :locked }.fetch(state.raw['SignalDoor'], :unknown)

      # @param bytes [String] +ExtendedState+ past its first 3 bytes
      # @param state [State]
      # @return [Reading]
      def reading(bytes, state)
        mode = bytes.getbyte(59).to_i
        energy, water = bytes.unpack('@47nn')
        Reading.new(load: bytes.getbyte(0), soiling: bytes.getbyte(63), drying_level: bytes.getbyte(58),
                    washing: mode[1] == 1, drying: mode[0] == 1, eco: bytes.getbyte(62).to_i[0] == 1, energy:,
                    water:, temperature: temperature(state), spin_speed: state.raw['SpinningSpeed'])
      end

      # The app shows 0 for a target beyond 0 to 100 °C.
      #
      # @param state [State]
      # @return [Integer]
      def temperature(state)
        celsius = state.raw['TargetTemperature']&.first.to_i / 100
        (0..100).cover?(celsius) ? celsius : 0
      end
    end
  end
end
