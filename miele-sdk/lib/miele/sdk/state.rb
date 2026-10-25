# frozen_string_literal: true

module Miele
  module Sdk
    # What an appliance is doing, read from its +State+ resource.
    #
    # @example Read how long an oven still runs
    #   Miele::Sdk.appliance('192.0.2.20').state.remaining_time # => 5400
    class State
      # One cooking zone of a hob.
      #
      # @!attribute [r] step
      #   @return [Integer, nil] power level as the appliance encodes it, not always the displayed one
      # @!attribute [r] remaining_heat
      #   @return [Integer, nil] residual heat, from 0 (none) to 3 (high)
      # @!attribute [r] remaining_minutes
      #   @return [Integer, nil]
      # @!attribute [r] elapsed_minutes
      #   @return [Integer, nil]
      # @!attribute [r] timer_seconds
      #   @return [Integer, nil]
      Plate = Data.define(:step, :remaining_heat, :remaining_minutes, :elapsed_minutes, :timer_seconds)

      PLATE_KEYS = %w[PlateStep PlateRemainingHeat PlateRemainingMinutes PlateElapsedMinutes PlateTimerSeconds].freeze
      private_constant :PLATE_KEYS

      # Miele's marker for a temperature the appliance does not measure right now.
      ABSENT = -32_768
      private_constant :ABSENT

      LIGHT = { 1 => :on, 2 => :off }.freeze
      private_constant :LIGHT

      # @return [Hash{String=>Object}] the resource as the appliance served it
      attr_reader :raw

      # @return [Symbol] device type, which selects the phase table
      attr_reader :device_type

      # @return [Integer, nil] +ProtocolVersion+ of the appliance, which selects the program type table
      attr_reader :protocol_version

      # @return [String, nil] +TechType+ of the appliance, which selects a Dop1 oven's program table
      attr_reader :tech_type

      # @param raw [Hash{String=>Object}] the +State+ resource
      # @param device_type [Symbol] one of {Catalog::DEVICE_TYPES}
      # @param protocol_version [Integer, nil] +ProtocolVersion+ of the appliance's +Ident+
      # @param tech_type [String, nil] +TechType+ of the appliance's +Ident+ device label
      def initialize(raw, device_type, protocol_version: nil, tech_type: nil)
        @raw = raw
        @device_type = device_type
        @protocol_version = protocol_version
        @tech_type = tech_type
      end

      # @return [Symbol] one of {Catalog::STATUS} or of the device type's {Catalog::DEVICE_STATUS}, or +:unknown+
      # @api public
      def status = Catalog::STATUS[raw['Status']] || Catalog::DEVICE_STATUS.dig(device_type, raw['Status']) || :unknown

      # @return [Symbol] one of {Catalog::PROGRAM_TYPES}, or of {Catalog::DOP2_PROGRAM_TYPES} on a DOP2
      #   appliance, or +:unknown+
      # @api public
      def program_type
        (dop2? ? Catalog::DOP2_PROGRAM_TYPES : Catalog::PROGRAM_TYPES).fetch(raw['ProgramType'], :unknown)
      end

      # @return [Integer, nil] +ProgramID+ of the selected program
      # @api public
      def program_id = raw['ProgramID']

      # @return [Symbol] name from {Catalog::DOP2_OVEN_PROGRAMS} on a DOP2 oven, from the
      #   {Catalog::DOP1_OVEN_TABLES} table of a Dop1 oven, from {Catalog::PROGRAMS} on other
      #   appliances the Miele app names programs of, or +:unknown+
      # @api public
      def program = programs.fetch(program_id, :unknown)

      # @return [Symbol] phase from the table of the device type's family, or +:unknown+
      # @api public
      def program_phase
        family = Catalog::PHASE_FAMILIES[device_type] or return :unknown
        Catalog::PROGRAM_PHASES.fetch(family).find { |_, codes| codes.include?(raw['ProgramPhase']) }&.first || :unknown
      end

      # @return [Integer, nil] seconds until the program ends
      # @api public
      def remaining_time = seconds('RemainingTime')

      # @return [Integer, nil] seconds since the program started
      # @api public
      def elapsed_time = seconds('ElapsedTime')

      # @return [Integer, nil] seconds until a delayed start
      # @api public
      def start_time = seconds('StartTime')

      # @return [Array<Float, nil>] measured temperatures in °C, nil where the appliance measures none
      # @api public
      def temperatures = celsius('Temperature')

      # @return [Array<Float, nil>] target temperatures in °C, nil where none is set
      # @api public
      def target_temperatures = celsius('TargetTemperature')

      # @api public
      def door_open? = raw['SignalDoor'] == true

      # @api public
      def failure? = raw['SignalFailure'] == true

      # @return [Boolean] whether the appliance accepts commands (Mobile Controllable on)
      # @api public
      def remote_control? = raw.dig('RemoteEnable', 0).to_i.anybits?(1)

      # @return [Symbol, nil] +:on+, +:off+, or nil without a light
      # @api public
      def light = LIGHT[raw['Light']]

      # @return [Integer, nil] hood fan level, 0 (off) to 4
      # @api public
      def ventilation_step = raw['VentilationStep']

      # @return [Array<Plate>] hob cooking zones, empty on other appliances
      # @api public
      def plates = raw.fetch('PlateStep', []).each_index.map { |zone| Plate.new(*PLATE_KEYS.map { raw.dig(it, zone) }) }

      private

      # Most appliances send +[hours, minutes]+; ha-miele-at-lan reports some sending plain minutes.
      #
      # @param key [String]
      # @return [Integer, nil]
      def seconds(key)
        value = raw[key]
        minutes = value.is_a?(Array) ? (value.fetch(0) * 60) + value.fetch(1) : value
        minutes * 60 if minutes
      end

      # @param key [String] a field of hundredths of a degree
      # @return [Array<Float, nil>]
      def celsius(key) = raw.fetch(key, []).map { it / 100.0 unless it == ABSENT }

      # @return [Boolean]
      def dop2? = Catalog::DOP2_PROTOCOL_VERSIONS.include?(protocol_version)

      # @return [Hash{Integer=>Symbol}] program names of this appliance, empty when the Miele app names none
      def programs
        table = program_table
        table ? Catalog::PROGRAMS.fetch(table) : oven_programs
      end

      # @return [Symbol, nil] {Catalog::PROGRAMS} table of this appliance
      def program_table
        return Catalog::PROGRAM_TABLES[device_type] unless Catalog::DISHWASHER_TYPES.include?(device_type)

        if dop2? then :dishwasher_dop2
        elsif protocol_version == Catalog::DOP1_PROTOCOL_VERSION then :dishwasher_dop1
        end
      end

      # @return [Hash{Integer=>Symbol}] program names of this oven, empty for other appliances
      def oven_programs
        return Catalog::DOP2_OVEN_DEVICE_TYPES.include?(device_type) ? Catalog::DOP2_OVEN_PROGRAMS : {} if dop2?
        return {} unless protocol_version == Catalog::DOP1_PROTOCOL_VERSION

        tables = Catalog::DOP1_OVEN_TABLES[device_type] or return {}
        table = tables[device_class] || tables[nil] or return {}
        Catalog::DOP1_OVEN_PROGRAMS.fetch(table)
      end

      # @return [Integer, nil] device class the Miele app reads from the +TechType+
      def device_class
        digit = tech_type.to_s[/\A\D+\d(\d)\d\d/, 1] or return
        (digit.to_i + 1) / 2
      end
    end
  end
end
