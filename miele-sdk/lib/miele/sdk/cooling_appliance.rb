# frozen_string_literal: true

module Miele
  module Sdk
    # A fridge, freezer or wine unit, which the Miele app's refrigeration module handles (device types 19, 20, 21,
    # 32, 33, 34 and 68). Protocols 200 (BSH), 201 and 203 (Liebherr) serve the JSON +Cooling+ resource; an Opcode
    # appliance (0 and 1) shows its zones in +State+.
    class CoolingAppliance < Appliance
      include Zones
      include Pickers
      include Screen
      include Commands

      # A zone as the app shows it.
      #
      # @!attribute [r] number
      #   @return [Integer] its +Cooling/{n}+ number, or its place in an Opcode appliance's +State+ arrays
      # @!attribute [r] position
      #   @return [Integer] 1 top, 2 middle, 3 bottom
      # @!attribute [r] rank
      #   @return [Integer] its place among the zones sorted by position, from 1
      # @!attribute [r] type
      #   @return [Symbol] +:fridge+, +:freezer+, +:wine_cabinet+, +:vario_cool+…, +:unknown+
      # @!attribute [r] enabled
      #   @return [Boolean]
      # @!attribute [r] temperature
      #   @return [Float, nil] in {#temperature_unit}; nil off, or on protocol 200, where the app shows none
      # @!attribute [r] target
      #   @return [Float, nil]
      # @!attribute [r] super_mode
      #   @return [Boolean, nil] super cooling or freezing; nil without one
      # @!attribute [r] fan
      #   @return [Boolean, nil]
      # @!attribute [r] vario_cool
      #   @return [Boolean, nil]
      Zone = Data.define(:number, :position, :rank, :type, :enabled, :temperature, :target, :super_mode, :fan,
                         :vario_cool)

      # The eco, party, holiday, Sabbath or child-proof mode.
      #
      # @!attribute [r] on
      #   @return [Boolean]
      # @!attribute [r] editable
      #   @return [Boolean] whether the appliance lists values to set it to, which the app requires
      Mode = Data.define(:on, :editable)

      MODES = { eco: 'EcoMode', party: 'Party', holiday: 'Holiday', sabbath: 'Sabbath',
                child_proof: 'ChildProof' }.freeze
      # Each alarm's key in +Cooling+ and the value that raises it.
      ALARMS = { dust_filter: ['DustFilter', 3], air_filter: ['AirFilter', 3], water_filter: ['WaterFilter', 3],
                 ice_maker: ['IceMaker', 3], demo_mode: ['DemoMode', 1] }.freeze
      private_constant :MODES, :ALARMS

      # @return [Hash{String=>Object}] the +Cooling+ resource of protocols 200, 201 and 203
      # @api public
      def cooling = device('Cooling')

      # @return [Symbol, nil] +:celsius+ or +:fahrenheit+, nil while off; an Opcode appliance counts in °C
      # @api public
      def temperature_unit
        return :celsius if opcode?
        return unless on?

        cooling.dig('TempUnit', 'Value') == 2 ? :fahrenheit : :celsius
      end

      # @param state [State]
      # @return [Hash{Symbol=>Mode}] the modes the appliance lists, none while off or on Opcode
      # @api public
      def modes(state = self.state)
        listed = cooling_api? && on?(state) ? cooling : {} #: Hash[String, untyped]
        MODES.filter_map { |name, key| [name, mode(listed[key])] if [1, 2].include?(listed.dig(key, 'Value')) }.to_h
      end

      # @return [Array<Symbol>] filter, ice maker and demo alarms, none while off or on Opcode
      # @api public
      def alarms
        listed = cooling_api? && on? ? cooling : {} #: Hash[String, untyped]
        ALARMS.filter_map { |name, (key, value)| name if listed.dig(key, 'Value') == value }
      end

      # @return [Symbol, nil] +:on+, +:off+ or +:alarm+ on an appliance with an ice maker, nil otherwise or while off
      # @api public
      def ice_maker
        return unless ice_maker? && on?

        { 1 => :on, 2 => :off, 3 => :alarm }[cooling.dig('IceMaker', 'Value')]
      end

      # @return [Integer, nil] the door alarm delay in seconds
      # @api public
      def door_alarm_delay = cooling.dig('DoorAlarmTime', 'Value')

      # @return [Symbol, nil] +:on+ or +:off+ on a wine unit the app lights, nil otherwise
      # @api public
      def light
        return unless wine? && !rioja?

        { 1 => :on, 2 => :off }[state_light? ? state.raw['Light'] : cooling.dig('AmbientLightState', 'Value')]
      end

      # @return [Integer, nil] nil on protocol 201, where the app reads none
      # @api public
      def perfect_fresh = protocol_version == 201 ? nil : cooling.dig('PerfectFresh', 'Value')

      # @return [Symbol, nil] +:low+, +:medium+ or +:high+ on a KWTUS or Rioja wine unit, nil otherwise or while off
      # @api public
      def humidity
        return unless (rioja? || kwtus?) && on?

        { 1 => :low, 2 => :medium, 3 => :high }[cooling.dig('HumidityControl', 'Value')]
      end

      private

      # @param state [State]
      # @return [Boolean] not off (Status 1) nor disconnected (255)
      def on?(state = self.state) = ![1, 255].include?(state.raw['Status'])

      # @return [Boolean] protocols 0 and 1
      def opcode? = protocol_version.to_i <= 1

      # @return [Boolean] protocols 200, 201 and 203
      def cooling_api? = [200, 201, 203].include?(protocol_version)

      # @return [Boolean]
      def ice_maker? = cooling_api? && [20, 21, 33, 68].include?(identity.device_type)

      # @return [Boolean] device types 32, 33, 34 and 68
      def wine? = [32, 33, 34, 68].include?(identity.device_type)

      # @return [Boolean] the KWT 4, KWTS 4 and KWNS 4 wine units, which the app names Rioja
      def rioja? = ['KWTS 4', 'KWT 4', 'KWNS 4'].any? { tech_type.to_s.include?(it) }

      # @return [Boolean]
      def kwtus? = tech_type.to_s.include?('KWTUS')

      # @return [Boolean] a KWTUS or Rioja wine unit, but the KWT 4584 E
      def presentation_light? = (kwtus? || rioja?) && !tech_type.to_s.include?('KWT 4584 E')

      # @return [Boolean] a wine unit lit through +State+: Opcode, or protocol 201 or 203
      def state_light? = opcode? || [201, 203].include?(protocol_version)

      # @param value [Hash{String=>Object}]
      # @return [Mode]
      def mode(value) = Mode.new(on: value['Value'] == 1, editable: !Array(value['SetValues']).empty?)
    end
  end
end
