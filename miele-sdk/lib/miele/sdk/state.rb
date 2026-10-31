# frozen_string_literal: true

module Miele
  module Sdk
    # What an appliance is doing, read from its +State+ resource.
    #
    # @example Read how long an oven still runs
    #   Miele::Sdk.appliance('192.0.2.20').state.remaining_time # => 5400
    class State
      include RemoteControl

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

      # The Dop1 object the app builds from ExtendedState, by device type and ProtocolVersion, and the zero bytes it
      # puts first. DOP2 hobs (4) are read through DOP2 instead; the other families read their ExtendedState otherwise.
      EXTENDED_STATES = {
        [:hood, 1] => ['Hood::ExtendedOpCodeDeviceState', 0], [:hood, 2] => ['Hood::ExtendedDopDeviceState', 22],
        [:hood, 3] => ['Hood::ExtendedDop2DeviceState', 22], [:hood, 4] => ['Hood::ExtendedDop2DeviceState', 22],
        **%i[hob_highlight hob_induction hob_gas].product([1, 2]).to_h { [it, ['Hob::ExtendedDeviceState', 22]] }
      }.freeze
      private_constant :EXTENDED_STATES

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

      # @return [Data, nil] +ExtendedState+ as the app reads it, such as an {Objects::Hood::ExtendedDopDeviceState};
      #   nil for the families that read it otherwise, or when the appliance serves none
      # @api public
      def extended_state
        name, padding = EXTENDED_STATES[[device_type, protocol_version]]
        hex = raw['ExtendedState'].to_s
        Objects.const_get(name).from(("\0" * padding) + [hex].pack('H*')) unless name.nil? || hex.empty?
      end

      # @return [Schema::DeviceState] {#raw} as a typed value
      # @api public
      def attributes = Schema::DeviceState.from(raw)

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

      # @return [Symbol] name from the {Catalog::PROGRAMS} table the Miele app reads for this
      #   appliance, or +:unknown+
      # @api public
      def program
        table = program_table or return :unknown
        Catalog::PROGRAMS.fetch(table).fetch(program_id, :unknown)
      end

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

      # @return [Boolean]
      def dop1? = protocol_version == Catalog::DOP1_PROTOCOL_VERSION

      # @return [Symbol, nil] {Catalog::PROGRAMS} table of this appliance, nil when the Miele app names none
      def program_table
        return Catalog::PROGRAM_TABLES[device_type] if Catalog::PROGRAM_TABLES.key?(device_type)
        return unless protocol_version

        kind = Catalog::LAUNDRY_TYPES[device_type]
        return laundry_table(kind) if kind
        return oven_table if Catalog::OVEN_TYPES.include?(device_type)

        dishwasher_table if Catalog::DISHWASHER_TYPES.include?(device_type)
      end

      # @param kind [Symbol] one of {Catalog::LAUNDRY_TYPES}' values
      # @return [Symbol]
      def laundry_table(kind) = kind.end_with?('tumble_dryer') ? dryer_table(kind) : washer_table(kind)

      # @return [Symbol, nil]
      def oven_table
        return :oven_dop2 if dop2?
        return unless dop1?

        tables = Catalog::DOP1_OVEN_TABLES[device_type] or return
        tables[device_class] || tables[nil]
      end

      # @return [Symbol, nil]
      def dishwasher_table
        if dop2? then :dishwasher_dop2
        elsif dop1? then :dishwasher_dop1
        end
      end

      # Checked in the order of the Miele app's ProgramIdToNameLocalizationHelper.GetProgramIdLocalized.
      #
      # @param kind [Symbol] one of {Catalog::LAUNDRY_TYPES}' values
      # @return [Symbol]
      def dryer_table(kind)
        return :laundry_smartbiz_td if kind == :tumble_dryer && tech_type.to_s.match?(/PDR/i)
        return :laundry_semi_professional_td if kind == :semi_professional_tumble_dryer

        dop2? ? :laundry_dop2_td : :laundry_legacy_td
      end

      # @param kind [Symbol] one of {Catalog::LAUNDRY_TYPES}' values
      # @return [Symbol]
      def washer_table(kind)
        return :laundry_smartbiz_wm if kind == :washing_machine && tech_type.to_s.match?(/PWM/i)
        return :laundry_semi_professional_wm if kind == :semi_professional_washing_machine
        return :laundry_w2_discovery if kind == :washing_machine && w2_discovery?

        dop2? ? :laundry_dop2_wm : :laundry_legacy_wm
      end

      # @return [Boolean] whether this is a W1, W3 or W5 model on DOP2
      def w2_discovery? = dop2? && tech_type.to_s.match?(/\AW\s*[135]/i)

      # @return [Integer, nil] device class the Miele app reads from the +TechType+
      def device_class
        digit = tech_type.to_s[/\A\D+\d(\d)\d\d/, 1] or return
        (digit.to_i + 1) / 2
      end
    end
  end
end
