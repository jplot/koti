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

        # @param id [Integer] a profile, such as one of {#custom_profiles}
        # @param name [String]
        # @return [void]
        # @raise [ActionUnavailableError] on a CM7 or CVA6000, which have no 1/109 to write
        # @api public
        def rename_profile(id, name)
          require_profiles!
          write_profile(id, active: true, name:, clear_list: false, program_id: id, display_position: 255, type: 10)
        end

        # @param id [Integer]
        # @param name [String]
        # @return [Boolean] whether the app renames the profile so: a custom one, to a name neither blank, nor
        #   another profile's, nor Miele in any case
        # @api public
        def profile_name_allowed?(id, name)
          return false unless gen7? && CUSTOM_PROFILES.cover?(id)

          !name.strip.empty? && !profiles.except(id).values.map(&:name).include?(name) && name.upcase != 'MIELE'
        end

        # The app clears the name and marks the profile active.
        #
        # @param id [Integer] a profile, such as one of {#custom_profiles}
        # @return [void]
        # @raise [ActionUnavailableError] on a CM7 or CVA6000, which have no 1/109 to write
        # @api public
        def delete_profile(id)
          require_profiles!
          write_profile(id, name: '', active: true, clear_list: false)
        end

        # @param id [Integer]
        # @return [Boolean] whether the app deletes the profile: a custom one, while 2/348 lists coffee profiles
        # @api public
        def delete_profile_offered?(id)
          gen7? && CUSTOM_PROFILES.cover?(id) && features&.feature_co&.has_coffee_profiles == true
        end

        # @return [Array<Integer>] the profiles the app lets rename and delete, 24813 to 24822
        # @api public
        def custom_profiles = CUSTOM_PROFILES.to_a

        # A CVA takes the bean sort; the others 255, as the app writes them.
        #
        # @param id [Integer] the drink's program id
        # @param amount [Integer] such as one of {#drink_settings}
        # @param temperature [Integer]
        # @param pre_brewing [Integer]
        # @param bean_sort [Integer, nil] on a CVA; the one read otherwise
        # @return [void]
        # @raise [ArgumentError] for a value its 2/261 member does not hold
        # @raise [ActionUnavailableError] on a CM7 or CVA6000, which have no 2/261 to write
        # @api public
        def edit_drink(id, amount:, temperature:, pre_brewing:, bean_sort: nil)
          require_profiles!
          modify_dop2(Objects::CoffeeGen7::GlobalDrinkconfDrinkData, 2, 261, id, 0) do |drink|
            drink.with(amount_of_coffee: amount, bean_sort: variant == :cva ? bean_sort || drink.bean_sort : 255,
                       brew_speed: brew_speed(drink), temperature:, pre_brewing:)
          end
        end

        # @return [Hash{Symbol=>Array<Integer>}] what the app's pickers offer {#edit_drink}: amounts 0 to 100 in
        #   sixths, temperatures 0 to 4, pre-brewing 0 to 2
        # @api public
        def drink_settings = { amount: AMOUNTS, temperature: (0..4).to_a, pre_brewing: (0..2).to_a }

        # @param id [Integer] the drink's program id
        # @param name [String]
        # @return [void]
        # @raise [ActionUnavailableError] on a CM7 or CVA6000, which have no 1/109 to write
        # @api public
        def rename_drink(id, name)
          require_profiles!
          write_profile(id, active: true, clear_list: false, display_position: 255, name:)
        end

        # The app names a drink only on a CVA and outside the standard profile, and writes no blank name.
        #
        # @param id [Integer] the drink's program id
        # @param name [String]
        # @return [Boolean] whether the app names the drink so
        # @api public
        def drink_name_allowed?(id, name)
          return false unless variant == :cva && DRINKS.cover?(id) && !name.strip.empty?

          STANDARD_PROFILE + ((id - DRINKS.first) / 32) != STANDARD_PROFILE
        end

        private

        # @return [void]
        # @raise [ActionUnavailableError]
        def require_profiles! = require!(gen7?, 'a CM7 or CVA6000 has no profile or drink object to write')

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
