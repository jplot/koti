# frozen_string_literal: true

module Miele
  module Sdk
    class Hob < Appliance
      # A cooking zone, as the app shows it.
      #
      # @!attribute [r] number
      #   @return [Integer]
      # @!attribute [r] level
      #   @return [Float, nil] 0 to 12, in half steps when the hob doubles its levels; nil while it shows heat
      # @!attribute [r] heat
      #   @return [Symbol, nil] +:residual_h+, +:residual1+ to +:residual3+ (each also +_blinking+) or +:keep_warm+
      # @!attribute [r] booster
      #   @return [Integer] 0 (off) to 3
      # @!attribute [r] timer
      #   @return [Integer, nil] seconds
      # @!attribute [r] cookware
      #   @return [Boolean]
      # @!attribute [r] bridged
      #   @return [Boolean]
      # @!attribute [r] temp_control
      #   @return [Boolean]
      # @!attribute [r] secondary
      #   @return [Boolean] the zone of a bridged pair that the app's screen hides
      Zone = Data.define(:number, :level, :heat, :booster, :timer, :cookware, :bridged, :temp_control, :secondary)

      # TempControl, which keeps a zone at a temperature.
      #
      # @!attribute [r] zone
      #   @return [Integer]
      # @!attribute [r] level
      #   @return [Symbol] +:simmer+, +:one+, +:two+, +:three+, +:custom+ or +:none+
      # @!attribute [r] target_reached
      #   @return [Boolean]
      # @!attribute [r] target
      #   @return [Integer] whole °C, 0 where the hob reports none
      # @!attribute [r] current
      #   @return [Integer] whole °C, 0 where the hob reports none
      TempControl = Data.define(:zone, :level, :target_reached, :target, :current)

      # The fan of a hob with vapour extraction.
      #
      # @!attribute [r] level
      #   @return [Integer, Symbol, nil] 0 to 9, +:booster+, or nil for a level the app does not know
      # @!attribute [r] run_on
      #   @return [Integer] seconds
      Fan = Data.define(:level, :run_on)

      # How the app's hob module builds its zones (FromExtendedStateMapper, DeviceStateRule).
      module Zones
        HEATS = { 100 => :residual_h, 101 => :residual1, 102 => :residual2, 103 => :residual3,
                  104 => :residual_h_blinking, 105 => :residual1_blinking, 106 => :residual2_blinking,
                  107 => :residual3_blinking, 110 => :keep_warm }.freeze
        private_constant :HEATS

        private

        # @param general [Data] +Geraetespezifische_Informationen+
        # @param count [Integer] the zones the hob declares
        # @return [Array<Zone>] in the app's order: with four zones, zone 5 takes the fourth place while it heats
        def existing_zones(general, count)
          doubling = general.allg_kochfeldinformationen.leistungsstufenverdopplung == :aktiviert
          zones = (1..6).map { zone(general, it, doubling) }.first(count)
          zones[3] = zone(general, 5, doubling) if count == 4 && raw_level(general, 5).positive?
          zones
        end

        # @param general [Data]
        # @param number [Integer]
        # @param doubling [Boolean]
        # @return [Zone]
        def zone(general, number, doubling)
          raw = raw_level(general, number)
          info = general.public_send(:"info_kochstelle_kochstelle_#{number}")
          hint = general.public_send(:"fehler_hinweis_kochstelle_#{number}")
          ends = general.public_send(:"endzeit_kochstelle_#{number}").bytes.unpack1('n')
          Zone.new(number, level(raw, doubling), HEATS[raw], Objects::Hob::BoosterEnum.to_i(info.boosterfunktion),
                   timer(ends), info.topf_erkannt == :aktiviert, hint.kochstellenkoppelung == :aktiviert,
                   hint.temp_control == :aktiviert, false)
        end

        # @param general [Data]
        # @param number [Integer]
        # @return [Integer]
        def raw_level(general, number)
          Objects::Hob::KochstufeDeviceStateEnum.to_i(general.public_send(:"leistungsstufe_kochstelle_#{number}"))
        end

        # MapPowerLevel: 12 steps, or 23 half steps when the hob doubles them; 100 and above is heat.
        #
        # @param raw [Integer]
        # @param doubling [Boolean]
        # @return [Float, nil]
        def level(raw, doubling)
          return raw.to_f if !doubling && raw <= 12
          return unless doubling && raw <= 23

          raw.zero? ? 0.0 : (raw + 1) / 2.0
        end

        # The app shows the end time as a duration, whatever +Zeitart+ (bits 14 and 15) says.
        #
        # @param time [Integer] an +Endzeit+ or a DOP2 duration: hours in bits 0 to 7, minutes in 8 to 13
        # @return [Integer, nil] seconds
        def timer(time) = (((time & 0xFF) * 3600) + (((time >> 8) & 0x3F) * 60)).nonzero?

        # GetFlexZones pairs the zones by place, CheckAndSynchronizeTimerOfCoupledCooktops and
        # FlagSecondariesInFlexZones then rule on each bridged pair.
        #
        # @param zones [Array<Zone>] in the app's order
        # @return [Array<Zone>]
        def flexed(zones)
          zones.each_slice(2).flat_map do |pair|
            next pair unless pair.size == 2 && pair.all?(&:bridged)

            timer = pair.fetch(0).timer || pair.fetch(1).timer
            secondary = secondary_of(pair)
            pair.map { it.with(timer:, secondary: it.equal?(secondary)) }
          end
        end

        # @param pair [Array<Zone>] two bridged zones
        # @return [Zone, nil] the one not boosted when the other is, else the second
        def secondary_of(pair) = pair.one? { it.booster.positive? } ? pair.find { it.booster.zero? } : pair.fetch(1)

        # The app numbers the zones of a hob with zone controls from them (+Topfdaten+), and gives the others
        # the lowest numbers left.
        #
        # @param zones [Array<Zone>]
        # @param values [Data] the whole ExtendedState
        # @return [Array<Zone>]
        def renumbered(zones, values)
          numbers = zones.each_index.map do |index|
            control = values.public_send(:"topfdaten_#{index + 1}").allgemein.nummer_des_bedienelements
            Objects::Hob::BedienelementEnum.to_i(control)
          end
          free = (1..6).to_a - numbers
          zones.each_with_index.map do |zone, index|
            number = numbers.fetch(index)
            zone.with(number: number.positive? ? number : free.shift)
          end
        end
      end
    end
  end
end
