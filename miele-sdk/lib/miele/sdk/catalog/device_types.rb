# frozen_string_literal: true

module Miele
  module Sdk
    # Values the appliances report, translated to names.
    module Catalog
      # +DeviceType+ of an appliance's +Ident+, as Miele publishes it
      # (developer.miele.com, capabilities by device), plus the professional
      # models and the second steam oven generation Home Assistant lists.
      DEVICE_TYPES = {
        1 => :washing_machine, 2 => :tumble_dryer, 3 => :washing_machine_semi_professional,
        4 => :tumble_dryer_semi_professional, 5 => :washing_machine_professional, 6 => :tumble_dryer_professional,
        7 => :dishwasher, 8 => :dishwasher_semi_professional, 9 => :dishwasher_professional,
        12 => :oven, 13 => :oven_microwave, 14 => :hob_highlight, 15 => :steam_oven, 16 => :microwave,
        17 => :coffee_system, 18 => :hood, 19 => :fridge, 20 => :freezer, 21 => :fridge_freezer,
        23 => :robot_vacuum, 24 => :washer_dryer, 25 => :dish_warmer, 27 => :hob_induction,
        31 => :steam_oven_combination, 32 => :wine_cabinet, 33 => :wine_conditioning_unit,
        34 => :wine_storage_conditioning_unit, 45 => :steam_oven_microwave_combination, 67 => :dialog_oven,
        68 => :wine_cabinet_freezer, 73 => :steam_oven_mk2, 74 => :hob_with_vapour_extraction
      }.freeze
    end
  end
end
