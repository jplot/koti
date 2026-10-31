# frozen_string_literal: true

module Miele
  module Sdk
    # A washing machine or washer-dryer, which the Miele app's laundry module handles (device types 1, 3 and
    # 24).
    class WashingMachine < Appliance
      DOP2_EXTRAS = %i[intensive eco extra_quiet allergo_wash soak quick rinse_hold pre_wash water_plus rinsing_plus
                       steam_smoothing pre_rinse microfibre single gentle hygiene_plus].freeze
      DOP1_EXTRAS = { eco: :extra_eco, intensive: :extra_intensiv, gentle: :extra_schonen,
                      allergo_wash: :extra_keine_seife, soak: :extra_einweichen, short: :extra_kurz,
                      rinse_hold: :extra_spuelstop, pre_wash: :extra_vorwaesche, water_plus: :extra_wasser_plus,
                      rinsing_plus: :extra_spuelen_plus, steam_smoothing: :extra_dampfglaetten }.freeze
      # Each stain's flag on DOP2 and bit on Dop1.
      STAINS = { blood: [0x1, :extra_flecken_blut], cola: [0x2, :extra_flecken_cola], egg: [0x4, :extra_flecken_ei],
                 fat: [0x8, :extra_flecken_fett], fruit_vegetable_juice: [0x10, :extra_flecken_frucht_gemuese],
                 vegetable: [0x20, :extra_flecken_gemuese], grass: [0x40, :extra_flecken_gras],
                 coffee: [0x80, :extra_flecken_kaffee], cocoa: [0x100, :extra_flecken_kakao],
                 ketchup: [0x200, :extra_flecken_ketchup], collar_soiling: [0x400, :extra_flecken_kragenschmutz],
                 lipstick: [0x800, :extra_flecken_lippenstift], make_up: [0x1000, :extra_flecken_makeup],
                 mayonnaise: [0x2000, :extra_flecken_mayonnaise], fruit: [0x4000, :extra_flecken_obst],
                 oil_grease: [0x8000, :extra_flecken_oele], red_wine: [0x10000, :extra_flecken_rotwein],
                 sand_soil: [0x20000, :extra_flecken_sand_und_erde], chocolate: [0x40000, :extra_flecken_schokolade],
                 sweat: [0x80000, :extra_flecken_schweiss], tea: [0x100000, :extra_flecken_tee],
                 urine: [0x200000, :extra_flecken_urin], universal: [0x400000, :extra_flecken_universal] }.freeze
      private_constant :DOP2_EXTRAS, :DOP1_EXTRAS, :STAINS

      include Laundry
      include Parameters
      include Dop1Parameters

      # @return [Hash{String=>Object}, nil] the TwinDos trays, from +services+, which the app reads on washers only
      # @api public
      def twin_dos = services['TwinDos']

      # @param levels [Array<Hash{Symbol=>Integer}>] each container's +:number+ and filling level in +:percent+
      # @api public
      def twin_dos_levels=(levels)
        body = levels.map { { number: it.fetch(:number), containerFillingLevelPercent: it.fetch(:percent) } }
        send_request(:post, "/Devices/#{fab}/services/TwinDos", body: JSON.generate(body))
      end

      private

      # @return [Hash{Symbol=>Class}]
      def dop1_objects
        { list: Objects::Laundry::WaProgrammliste, selection: Objects::Laundry::WaProgrammwahlLesen,
          write: Objects::Laundry::WaProgrammwahlSetzen }
      end

      # @param prog_id [Integer, Symbol]
      # @return [Data] 8201's write section, version 1
      def dop1_selection(prog_id)
        blank(Objects::Laundry::WaProgrammwahlSetzen::SettingsWriteSection).with(version: 1, programm_id: prog_id)
      end
    end
  end
end
