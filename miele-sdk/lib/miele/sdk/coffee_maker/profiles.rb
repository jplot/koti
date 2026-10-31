# frozen_string_literal: true

module Miele
  module Sdk
    class CoffeeMaker < Appliance
      # Coffee profiles and drinks as the app's coffee module writes them on a coffee maker but a CM7: 1/109 and
      # 2/261 at idx1 = the profile's or the drink's id, through ModifyDop2Message.
      module Profiles
        FIRST_CUSTOM = 24_813
        CUSTOM_PROFILES = (FIRST_CUSTOM..24_822)
        # The 32 drinks of each profile from the standard one on.
        DRINKS = (24_000..24_351)
        AMOUNTS = [0, 17, 33, 50, 67, 83, 100].freeze
        private_constant :FIRST_CUSTOM, :CUSTOM_PROFILES, :DRINKS, :AMOUNTS

        # The app takes the first id its profile chain leaves free: 4 on a CM6160, 8 on another CM6F, 10 otherwise.
        #
        # @param name [String]
        # @return [void]
        # @raise [ActionUnavailableError] on a CM7 or CVA6000, or without a free id
        # @api public
        def create_profile(name)
          require_profiles!
          used = profiles.keys
          id = (FIRST_CUSTOM...(FIRST_CUSTOM + profile_slots)).find { !used.include?(it) }
          require!(id, 'the coffee maker has no free profile')
          write_profile(id.to_i, active: false, name:, clear_list: false, program_id: id, display_position: 255,
                                 type: 10)
        end

        # @param id [Integer] a custom profile, 24813 to 24822
        # @param name [String]
        # @return [void]
        # @raise [ArgumentError] for another profile, a blank name, another profile's, or Miele in any case
        # @raise [ActionUnavailableError] on a CM7 or CVA6000
        # @api public
        def rename_profile(id, name)
          require_custom!(id)
          taken = profiles.except(id).values.map(&:name)
          if name.strip.empty? || taken.include?(name) || name.upcase == 'MIELE'
            raise ArgumentError, "#{name.inspect} is blank, taken or reserved"
          end

          write_profile(id, active: true, name:, clear_list: false, program_id: id, display_position: 255, type: 10)
        end

        # The app clears the name and marks the profile active.
        #
        # @param id [Integer] a custom profile, 24813 to 24822
        # @return [void]
        # @raise [ArgumentError] for another profile
        # @raise [ActionUnavailableError] on a CM7 or CVA6000, or unless 2/348 lists coffee profiles
        # @api public
        def delete_profile(id)
          require_custom!(id)
          require!(features&.feature_co&.has_coffee_profiles == true,
                   'the coffee maker lists no coffee profiles to delete')
          write_profile(id, name: '', active: true, clear_list: false)
        end

        # A CVA takes the bean sort; the others 255.
        #
        # @param id [Integer] the drink's program id
        # @param amount [Integer] 0, 17, 33, 50, 67, 83 or 100
        # @param temperature [Integer] 0 to 4
        # @param pre_brewing [Integer] 0 to 2
        # @param bean_sort [Integer, nil] on a CVA; the one read otherwise
        # @return [void]
        # @raise [ArgumentError] for a value the app does not offer
        # @raise [ActionUnavailableError] on a CM7 or CVA6000
        # @api public
        def edit_drink(id, amount:, temperature:, pre_brewing:, bean_sort: nil)
          require_profiles!
          unless AMOUNTS.include?(amount) && (0..4).cover?(temperature) && (0..2).cover?(pre_brewing)
            raise ArgumentError, 'the app offers amounts 0 to 100 in sixths, temperatures 0 to 4, pre-brewing 0 to 2'
          end

          modify_dop2(Objects::CoffeeGen7::GlobalDrinkconfDrinkData, 2, 261, id, 0) do |drink|
            drink.with(amount_of_coffee: amount, bean_sort: variant == :cva ? bean_sort || drink.bean_sort : 255,
                       brew_speed: brew_speed(drink), temperature:, pre_brewing:)
          end
        end

        # The app names a drink only on a CVA and outside the standard profile.
        #
        # @param id [Integer] the drink's program id
        # @param name [String] not blank, as the app writes no other
        # @return [void]
        # @raise [ArgumentError] for a blank name, or a drink no profile holds
        # @raise [ActionUnavailableError] on another coffee maker, or for a drink of the standard profile
        # @api public
        def rename_drink(id, name)
          if name.strip.empty? || !DRINKS.cover?(id)
            raise ArgumentError, "#{name.inspect} is blank, or #{id} no profile's drink"
          end

          profile = STANDARD_PROFILE + ((id - DRINKS.first) / 32)
          require!(variant == :cva && profile != STANDARD_PROFILE, 'the app names no such drink')
          write_profile(id, active: true, clear_list: false, display_position: 255, name:)
        end

        private

        # @return [void]
        # @raise [ActionUnavailableError]
        def require_profiles! = require!(gen7?, 'the app keeps no profiles or drinks on this coffee maker')

        # @param id [Integer]
        # @return [void]
        # @raise [ArgumentError] for the standard profile or none
        def require_custom!(id)
          require_profiles!
          raise ArgumentError, "#{id} is not a custom profile" unless CUSTOM_PROFILES.cover?(id)
        end

        # @return [Integer]
        def profile_slots
          return 10 unless variant == :cm6f

          tech_type.to_s == 'CM6160' ? 4 : 8
        end

        # @param id [Integer]
        # @param values [Hash{Symbol=>Object}] +GlobalOpProgramName+ members
        # @return [void]
        def write_profile(id, **values)
          modify_dop2(Objects::CoffeeGen7::GlobalOpProgramName, 1, 109, id, 0) { it.with(**values) }
        end

        # The app keeps the brew speed unless it is 255, then takes 50 when one of the first four phases brews
        # (type 3), else 0.
        #
        # @param drink [Objects::CoffeeGen7::GlobalDrinkconfDrinkData]
        # @return [Integer]
        def brew_speed(drink)
          return drink.brew_speed unless drink.brew_speed == 255

          types = drink.drink_phase.to_a.first(4).map(&:phase_type).compact
          types.any? { Objects::CoffeeGen7::GlobalEnumDrinkConfigPhaseType.to_i(it) == 3 } ? 50 : 0
        end
      end
    end
  end
end
