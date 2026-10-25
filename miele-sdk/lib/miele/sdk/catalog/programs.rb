# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +ProgramID+ of appliances other than ovens, by program table, named as the
      # Miele app (4.19.0) titles them in its default English. Dishwashers number
      # their programs one way under DOP2 and another under Dop1; a coffee system's
      # table covers the drinks of its standard profile, since the drinks of other
      # profiles are numbered as their owner arranged them.
      PROGRAMS = File.readlines("#{__dir__}/programs.tsv", chomp: true)
                     .map { it.split("\t") }.group_by(&:first).to_h do |table, rows|
        [table.to_s.to_sym, rows.to_h { |_, id, name| [Integer(id), name.to_s.to_sym] }.freeze]
      end.freeze

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

      # {PROGRAMS} table of the other device types the Miele app names programs of.
      PROGRAM_TABLES = { dish_warmer: :dish_warmer, coffee_system: :coffee }.freeze
    end
  end
end
