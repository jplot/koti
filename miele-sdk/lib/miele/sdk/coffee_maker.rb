# frozen_string_literal: true

module Miele
  module Sdk
    # A coffee maker, which the Miele app's coffee module handles (device type 17): a CM7, CM6F, CVA or CVA Ref2
    # over DOP2, and a CVA6000 over Dop1. A CM7 reads its objects on unit 2 from the +CoffeeCm7+ family, the
    # others on unit 1 from +CoffeeGen7+; the app reads a CM7 no cleaning, descaling, feature, ident, profile or
    # drink.
    class CoffeeMaker < Appliance
      include Commands
      include Brewing

      CM6F = %w[CM6360 CM6160 CM6560].freeze
      # The app tests Ref2's CVA73 and CVA74 before CVA7.
      PREFIXES = { cm7: %w[CM7], cva_ref2: %w[CVA74 CVA73], cva: %w[CVA7] }.freeze
      STANDARD_PROFILE = 24_812
      LAST_PROFILE = 24_822
      private_constant :CM6F, :PREFIXES, :STANDARD_PROFILE, :LAST_PROFILE

      # DetermineCoffeeMakerType, on the TechType without whitespace in upper case.
      #
      # @return [Symbol] +:cm7+, +:cm6f+, +:cva_ref2+, +:cva+, +:cva6000+ or +:unknown+
      # @api public
      def variant
        type = tech_type.to_s.gsub(/\s/, '').upcase
        return type.start_with?('CVA6') ? :cva6000 : :unknown if protocol_version == 2

        dop2? ? dop2_variant(type) : :unknown
      end

      # @return [Data, nil] 2/1586 at 0/0, nil on a CVA6000
      # @api public
      def combi_state = dop2? ? object(family::GlobalDeviceCombiState, [2, 1586, 0, 0]) : nil

      # @return [Data, nil] 1574 at 0/1 on the coffee maker's unit, nil on a CVA6000
      # @api public
      def program_context = dop2? ? object(family::GlobalPsContext, [unit, 1574, 0, 1]) : nil

      # @return [Data, nil] 1585 at 0/8 on the coffee maker's unit, nil on a CVA6000
      # @api public
      def context = dop2? ? object(family::GlobalDeviceContext, [unit, 1585, 0, 8]) : nil

      # @return [Data, nil] 131 at 0/1 on the coffee maker's unit, nil on a CVA6000
      # @api public
      def notifications = dop2? ? object(family::GlobalNtfctnShow, [unit, 131, 0, 1]) : nil

      # @return [Objects::CoffeeGen7::GlobalCleaningInformationCO, nil] 2/289 at 0/1
      # @api public
      def cleaning = gen7_object(Objects::CoffeeGen7::GlobalCleaningInformationCO, [2, 289, 0, 1])

      # @return [Objects::CoffeeGen7::GlobalDescalingInformationCO, nil] 2/288 at 0/3
      # @api public
      def descaling = gen7_object(Objects::CoffeeGen7::GlobalDescalingInformationCO, [2, 288, 0, 3])

      # @return [Objects::CoffeeGen7::GlobalFeatureList, nil] 2/348 at 0/0
      # @api public
      def features = gen7_object(Objects::CoffeeGen7::GlobalFeatureList, [2, 348, 0, 0])

      # @return [Objects::CoffeeGen7::GlobalDeviceIdent, nil] 2/144 at 0/0
      # @api public
      def device_ident = gen7_object(Objects::CoffeeGen7::GlobalDeviceIdent, [2, 144, 0, 0])

      # @param id [Integer] the drink's program id
      # @return [Objects::CoffeeGen7::GlobalDrinkconfDrinkData, nil] 2/261 at idx1 = id, idx2 0
      # @api public
      def drink(id) = gen7_object(Objects::CoffeeGen7::GlobalDrinkconfDrinkData, [2, 261, id, 0])

      # @param id [Integer] the drink's program id
      # @return [Objects::CoffeeGen7::GlobalDrinkconfDrinkThresholds, nil] 2/331 at idx1 = id, idx2 0
      # @api public
      def drink_limits(id) = gen7_object(Objects::CoffeeGen7::GlobalDrinkconfDrinkThresholds, [2, 331, id, 0])

      # The app reads 1/109 from the standard profile on, each instance's idx2 naming the next, until one names
      # itself or passes the last profile.
      #
      # @return [Array<Objects::CoffeeGen7::GlobalOpProgramName>] the standard profile first, none on a CM7
      # @api public
      def profiles
        found = [] #: Array[untyped]
        current = STANDARD_PROFILE
        while gen7?
          leaf = dop2(1, 109, idx1: current, idx2: 0)
          found << Objects::CoffeeGen7::GlobalOpProgramName.from(leaf.fields)
          return found if leaf.idx1 == leaf.idx2 || leaf.idx2 == current || leaf.idx2 > LAST_PROFILE

          current = leaf.idx2
        end
        found
      end

      # @return [Objects::CoffeeGen7::DeviceState, nil] Dop1 1000 on a CVA6000
      # @api public
      def device_state = variant == :cva6000 ? dop1_object(Objects::CoffeeGen7::DeviceState) : nil

      # @return [Objects::CoffeeGen7::ServiceExtCVAUsageCounter, nil] Dop1 8D00 on a CVA6000
      # @api public
      def usage_counters = variant == :cva6000 ? dop1_object(Objects::CoffeeGen7::ServiceExtCVAUsageCounter) : nil

      private

      # @return [Boolean] protocols 3 and 4
      def dop2? = [3, 4].include?(protocol_version)

      # @param type [String] the TechType without whitespace, in upper case
      # @return [Symbol]
      def dop2_variant(type)
        return :cm6f if CM6F.include?(type)

        PREFIXES.find { |_, prefixes| type.start_with?(*prefixes) }&.first || :unknown
      end

      # @return [Boolean] a DOP2 coffee maker but a CM7, an unknown one included, as the app's sources claim it
      def gen7? = dop2? && variant != :cm7

      # @return [Module] +Objects::CoffeeCm7+ or +Objects::CoffeeGen7+
      def family = variant == :cm7 ? Objects::CoffeeCm7 : Objects::CoffeeGen7

      # @return [Integer] 2 on a CM7, 1 on the others
      def unit = variant == :cm7 ? 2 : 1

      # @param klass [Class]
      # @param address [Array<Integer>]
      # @return [Data, nil]
      def gen7_object(klass, address) = gen7? ? object(klass, address) : nil
    end
  end
end
