# frozen_string_literal: true

module Miele
  module Sdk
    # Values the appliances report, translated to names.
    module Catalog
      # +DeviceType+ of an appliance's +Ident+: the 74 values of the Miele app's +DeviceType+ enum. Names taken
      # earlier from Miele's published capabilities and from Home Assistant stay; the others are the app's own.
      DEVICE_TYPES = {
        1 => :washing_machine, 2 => :tumble_dryer, 3 => :washing_machine_semi_professional,
        4 => :tumble_dryer_semi_professional, 5 => :washing_machine_professional, 6 => :tumble_dryer_professional,
        7 => :dishwasher, 8 => :dishwasher_semi_professional, 9 => :dishwasher_professional, 10 => :range_cooker,
        11 => :range_cooker_microwave, 12 => :oven, 13 => :oven_microwave, 14 => :hob_highlight, 15 => :steam_oven,
        16 => :microwave, 17 => :coffee_system, 18 => :hood, 19 => :fridge, 20 => :freezer, 21 => :fridge_freezer,
        22 => :chest_freezer, 23 => :robot_vacuum, 24 => :washer_dryer, 25 => :dish_warmer, 26 => :beverage_maker,
        27 => :hob_induction, 28 => :hob_gas, 29 => :hob_highlight_induction_combi, 30 => :hob_highlight_gas_combi,
        31 => :steam_oven_combination, 32 => :wine_cabinet, 33 => :wine_conditioning_unit,
        34 => :wine_storage_conditioning_unit, 35 => :water_dispenser, 36 => :ice_maker, 37 => :ice_crusher,
        38 => :cellar_compartment, 39 => :electrical_oven_double, 40 => :steam_oven_double,
        41 => :steam_oven_combination_double, 42 => :microwave_double, 43 => :electrical_oven_microwave_double,
        44 => :cleaner_disinfector, 45 => :steam_oven_microwave_combination, 46 => :remote_control,
        47 => :voice_control, 48 => :vacuum_drawer, 49 => :tepan, 51 => :washing_maschine_semi_professional_deprecated,
        52 => :tumble_dryer_semi_professional_deprecated, 53 => :washing_maschine_professional_deprecated,
        54 => :tumble_dryer_professional_deprecated, 60 => :washer_disinfector_medical_laboratory,
        61 => :washer_disinfector_medical_medical, 62 => :endo_thermal_disinfector, 63 => :table_top_sterilizer,
        64 => :steam_large_sterilizer, 65 => :container_trolley_washer, 66 => :steam_large_disinfector,
        67 => :dialog_oven, 68 => :wine_cabinet_freezer, 69 => :biofresh, 70 => :biofresh_freezer_combination,
        71 => :vertical_farm, 72 => :vacuum_cleaner, 73 => :steam_oven_mk2, 74 => :hob_with_vapour_extraction,
        75 => :vacuum_cleaner_cleaning_station, 76 => :vario_cool, 77 => :general_cooling, 78 => :grill_unit,
        79 => :laundry_care_cabinet, 92 => :ironing_station
      }.freeze

      # +ProtocolVersion+ of an appliance's +Ident+, named as the Miele app names it.
      PROTOCOLS = {
        1 => :opcode, 2 => :dop1, 3 => :dop2_mbus, 4 => :dop2_hdr, 6 => :maci, 200 => :dbus_cooling,
        201 => :tod_cooling, 203 => :lhb_tod2_cooling
      }.freeze
    end
  end
end
