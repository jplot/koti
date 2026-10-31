# frozen_string_literal: true

module Miele
  module Sdk
    # A tumble dryer, which the Miele app's laundry module handles (device types 2 and 4).
    class TumbleDryer < Appliance
      include Laundry

      private

      # @return [Hash{Symbol=>Class}]
      def dop1_objects = { list: Objects::Laundry::TdProgrammliste, selection: Objects::Laundry::TdProgrammwahlLesen }
    end
  end
end
