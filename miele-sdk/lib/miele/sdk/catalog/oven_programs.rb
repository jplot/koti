# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +ProgramID+ of DOP2 ovens, named after the oven menus of the Miele app
      # (4.19.0) in its default English: a program nested under a dish takes
      # the dish's name first, as the app shows it.
      OVEN_PROGRAMS = File.readlines("#{__dir__}/oven_programs.tsv", chomp: true).to_h do |line|
        id, name = line.split("\t", 2)
        [Integer(id), name.to_s.to_sym]
      end.freeze

      # Device types whose DOP2 +ProgramID+ {OVEN_PROGRAMS} names.
      OVEN_DEVICE_TYPES = %i[
        oven dialog_oven oven_microwave steam_oven steam_oven_combination steam_oven_mk2
        steam_oven_microwave_combination
      ].freeze
    end
  end
end
