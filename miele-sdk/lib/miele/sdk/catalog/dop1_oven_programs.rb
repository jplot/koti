# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +ProgramID+ of Dop1 ovens by program table, named as the Miele app
      # (4.19.0) titles them in its default English. Several ids of one dish
      # share its name, since the app shows no more.
      DOP1_OVEN_PROGRAMS = File.readlines("#{__dir__}/dop1_oven_programs.tsv", chomp: true)
                               .map { it.split("\t") }.group_by(&:first).to_h do |table, rows|
        [table.to_s.to_sym, rows.to_h { |_, id, name| [Integer(id), name.to_s.to_sym] }.freeze]
      end.freeze

      # {DOP1_OVEN_PROGRAMS} table of each Dop1 oven type, by device class:
      # the third digit of the +TechType+ halved, so that H2160B is class 1.
      # The +nil+ entry serves every other class.
      DOP1_OVEN_TABLES = {
        oven: { 1 => :bo_r1, nil => :bo }, oven_microwave: { nil => :bm }, steam_oven: { nil => :dg },
        steam_oven_combination: { 2 => :dgc_r2, nil => :dgc }, steam_oven_microwave_combination: { nil => :dgm }
      }.freeze
    end
  end
end
