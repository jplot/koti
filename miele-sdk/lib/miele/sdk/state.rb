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

      # @param raw [Hash{String=>Object}] the +State+ resource
      # @param device_type [Symbol] one of {Catalog::DEVICE_TYPES}
      def initialize(raw, device_type)
        @raw = raw
        @device_type = device_type
      end

      # @return [Symbol] one of {Catalog::STATUS} or of the device type's {Catalog::DEVICE_STATUS}, or +:unknown+
      # @api public
      def status = Catalog::STATUS[raw['Status']] || Catalog::DEVICE_STATUS.dig(device_type, raw['Status']) || :unknown

      # @return [Symbol] one of {Catalog::PROGRAM_TYPES}, or +:unknown+
      # @api public
      def program_type = Catalog::PROGRAM_TYPES.fetch(raw['ProgramType'], :unknown)

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
    end
  end
end
