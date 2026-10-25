# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # Phase table each device type reads its +ProgramPhase+ from.
      PHASE_FAMILIES = {
        washing_machine: :washing_machine, washing_machine_semi_professional: :washing_machine,
        washing_machine_professional: :washing_machine, tumble_dryer: :tumble_dryer,
        tumble_dryer_semi_professional: :tumble_dryer, tumble_dryer_professional: :tumble_dryer,
        washer_dryer: :washer_dryer, dishwasher: :dishwasher, dishwasher_semi_professional: :dishwasher,
        dishwasher_professional: :dishwasher, oven: :oven, dialog_oven: :oven, oven_microwave: :oven_microwave,
        steam_oven: :steam_oven, steam_oven_combination: :steam_oven_combination,
        steam_oven_mk2: :steam_oven_combination, steam_oven_microwave_combination: :steam_oven_microwave_combination,
        microwave: :microwave, coffee_system: :coffee_system, robot_vacuum: :robot_vacuum, dish_warmer: :dish_warmer
      }.freeze

      # +ProgramPhase+ codes by phase table. Miele publishes no phase list:
      # these come from Home Assistant core (homeassistant/components/miele/const.py).
      PROGRAM_PHASES = {
        washing_machine: {
          not_running: [0, 256, 65_535], pre_wash: [257, 259], soak: [258], main_wash: [260, 11_004],
          rinse: [261, 11_005], rinse_hold: [262], cleaning: [263], cooling_down: [264], drain: [265],
          spin: [266, 11_010], anti_crease: [267, 11_029], finished: [268, 11_012], venting: [269],
          starch_stop: [270], freshen_up_and_moisten: [271], steam_smoothing: [272, 295], hygiene: [279],
          drying: [280], disinfecting: [285], flex_load_active: [11_047], automatic_start: [11_044],
          paused: [11_052], cancelled: [11_053]
        },
        tumble_dryer: {
          not_running: [0, 512, 535, 536, 537, 65_535], program_running: [513], drying: [514, 11_018],
          machine_iron: [515], hand_iron2: [516], normal: [517], normal_plus: [518], cooling_down: [519],
          hand_iron1: [520], anti_crease: [521, 11_029], finished: [522, 11_012], extra_dry: [523],
          hand_iron: [524], hygiene_drying: [525], moisten: [526], thermo_spin: [527], timed_drying: [528],
          warm_air: [529], steam_smoothing: [530], comfort_cooling: [531, 11_055], rinse_out_lint: [532],
          rinses: [533], smoothing: [534], slightly_dry: [538], safety_cooling: [539], automatic_start: [11_044],
          perfect_dry_active: [11_054]
        },
        washer_dryer: {
          not_running: [0, 256, 512, 535, 536, 537, 65_535], pre_wash: [257, 259], soak: [258], main_wash: [260],
          rinse: [261], rinse_hold: [262], cleaning: [263], cooling_down: [264, 519], drain: [265], spin: [266],
          anti_crease: [267, 521], finished: [268, 522], venting: [269], starch_stop: [270],
          freshen_up_and_moisten: [271], steam_smoothing: [272, 295, 530], hygiene: [279], drying: [280, 514],
          disinfecting: [285], program_running: [513], machine_iron: [515], hand_iron2: [516], normal: [517],
          normal_plus: [518], hand_iron1: [520], extra_dry: [523], hand_iron: [524], moisten: [526],
          thermo_spin: [527], timed_drying: [528], warm_air: [529], comfort_cooling: [531], rinse_out_lint: [532],
          rinses: [533], smoothing: [534], slightly_dry: [538], safety_cooling: [539]
        },
        dishwasher: {
          not_running: [0, 1792, 65_535], reactivating: [1793], pre_dishwash: [1794, 1801], main_dishwash: [1795],
          rinse: [1796], interim_rinse: [1797], final_rinse: [1798], drying: [1799], finished: [1800]
        },
        oven: {
          not_running: [0, 65_535], heating_up: [3073], process_running: [3074], process_finished: [3078],
          searing: [3080], roasting: [3081], cooling_down: [3083], energy_save: [3084], pre_heating: [3099]
        },
        dish_warmer: {
          not_running: [0, 65_535], heating_up: [3073], door_open: [3075], keeping_warm: [3094],
          cooling_down: [3088]
        },
        microwave: {
          not_running: [0, 65_535], heating: [3329], process_running: [3330], process_finished: [3334],
          energy_save: [3340]
        },
        coffee_system: {
          not_running: [0, 4352, 65_535], heating_up: [3073], espresso: [4353], hot_milk: [4354], milk_foam: [4355],
          dispensing: [4361, 4404], pre_brewing: [4369], grinding: [4377], second_espresso: [4385],
          second_pre_brewing: [4393], second_grinding: [4401], rinse: [4405]
        },
        robot_vacuum: {
          not_running: [0, 65_535], vacuum_cleaning: [5889], returning: [5890], vacuum_cleaning_paused: [5891],
          going_to_target_area: [5892], wheel_lifted: [5893], dirty_sensors: [5894], dust_box_missing: [5895],
          blocked_drive_wheels: [5896], blocked_brushes: [5897], motor_overload: [5898], internal_fault: [5899],
          blocked_front_wheel: [5900], docked: [5903, 5904], remote_controlled: [5910]
        },
        oven_microwave: {
          not_running: [0, 65_535], steam_reduction: [3863], process_running: [3330, 7938],
          waiting_for_start: [7939], heating_up_phase: [3329, 7940], process_finished: [3334, 7942],
          cooling_phase: [3339], energy_save: [3340]
        },
        steam_oven: {
          not_running: [0, 65_535], steam_reduction: [3863], process_running: [7938], waiting_for_start: [7939],
          heating_up_phase: [7940], process_finished: [7942]
        },
        steam_oven_combination: {
          not_running: [0, 65_535], heating_up: [3073], process_running: [3074, 7938],
          process_finished: [3078, 7942], searing: [3080], roasting: [3081], energy_save: [3084],
          pre_heating: [3099], steam_reduction: [3863, 7959], waiting_for_start: [7939], heating_up_phase: [7940],
          drying: [7961], rinse: [7962]
        },
        steam_oven_microwave_combination: {
          not_running: [0, 65_535], heating: [3329], process_running: [3330, 7938, 7942], process_finished: [3334],
          energy_save: [3340], steam_reduction: [3863], waiting_for_start: [7939], heating_up_phase: [7940]
        }
      }.freeze
    end
  end
end
