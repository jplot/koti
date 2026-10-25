# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +ProgramID+ names by program table, as the Miele app (4.19.0) titles them
      # in its default English. A DOP2 oven program nested under a dish takes the
      # dish's name first, as the app's menus show it; a Dop1 oven table holds
      # the dish title only, so several ids share it. A coffee system's table
      # covers the drinks of its standard profile, since the drinks of other
      # profiles are numbered as their owner arranged them.
      PROGRAMS = File.readlines("#{__dir__}/programs.tsv", chomp: true)
                     .map { it.split("\t") }.group_by(&:first).to_h do |table, rows|
        [table.to_s.to_sym, rows.to_h { |_, id, name| [Integer(id), name.to_s.to_sym] }.freeze]
      end.freeze

      # Oven device types, which read {PROGRAMS} by protocol: +oven_dop2+, or
      # their {DOP1_OVEN_TABLES} table.
      OVEN_TYPES = %i[
        oven dialog_oven oven_microwave steam_oven steam_oven_combination steam_oven_mk2
        steam_oven_microwave_combination
      ].freeze

      # {PROGRAMS} table of each Dop1 oven type, by device class: the third
      # digit of the +TechType+ halved, so that H2160B is class 1. The +nil+
      # entry serves every other class.
      DOP1_OVEN_TABLES = {
        oven: { 1 => :oven_bo_r1, nil => :oven_bo }, oven_microwave: { nil => :oven_bm },
        steam_oven: { nil => :oven_dg }, steam_oven_combination: { 2 => :oven_dgc_r2, nil => :oven_dgc },
        steam_oven_microwave_combination: { nil => :oven_dgm }
      }.freeze

      # Dishwasher device types, which read {PROGRAMS} by protocol.
      DISHWASHER_TYPES = %i[dishwasher dishwasher_semi_professional dishwasher_professional].freeze

      # Laundry device types as the Miele app groups them to pick a {PROGRAMS}
      # table: professional models read the semi-professional tables.
      LAUNDRY_TYPES = {
        washing_machine: :washing_machine, tumble_dryer: :tumble_dryer, washer_dryer: :washer_dryer,
        washing_machine_semi_professional: :semi_professional_washing_machine,
        washing_machine_professional: :semi_professional_washing_machine,
        tumble_dryer_semi_professional: :semi_professional_tumble_dryer,
        tumble_dryer_professional: :semi_professional_tumble_dryer
      }.freeze

      # {PROGRAMS} table of the device types that read one whatever their protocol.
      PROGRAM_TABLES = { dish_warmer: :dish_warmer, coffee_system: :coffee }.freeze
    end
  end
end
