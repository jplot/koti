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

      private

      # @return [Hash{Symbol=>Class}]
      def dop1_objects = { list: Objects::Laundry::WaProgrammliste, selection: Objects::Laundry::WaProgrammwahlLesen }
    end
  end
end
