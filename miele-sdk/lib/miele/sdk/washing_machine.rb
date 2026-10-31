# frozen_string_literal: true

module Miele
  module Sdk
    # A washing machine or washer-dryer, which the Miele app's laundry module handles (device types 1, 3 and
    # 24).
    class WashingMachine < Appliance
      include Laundry

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
