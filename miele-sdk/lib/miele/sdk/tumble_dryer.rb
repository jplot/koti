# frozen_string_literal: true

module Miele
  module Sdk
    # A tumble dryer, which the Miele app's laundry module handles (device types 2 and 4).
    class TumbleDryer < Appliance
      include Laundry
      include Parameters

      private

      # @return [Hash{Symbol=>Class}]
      def dop1_objects
        { list: Objects::Laundry::TdProgrammliste, selection: Objects::Laundry::TdProgrammwahlLesen,
          write: Objects::Laundry::TdProgrammwahlSetzen }
      end

      # @param prog_id [Integer, Symbol]
      # @return [Data] 8602's write section, its structure version left at 0
      def dop1_selection(prog_id)
        blank(Objects::Laundry::TdProgrammwahlSetzen::SettingWriteSection).with(programm_id: prog_id)
      end
    end
  end
end
