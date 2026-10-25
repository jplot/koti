# frozen_string_literal: true

module Miele
  module Sdk
    # Live state changes pushed by the appliances of the household.
    module Events
      # Device type this host takes as a peer: the Miele panels do not list it.
      DEVICE_TYPE = 2_147_483_647

      # A change an appliance pushed.
      #
      # @!attribute [r] fab
      #   @return [String] fabrication number of the appliance that pushed it
      # @!attribute [r] resource
      #   @return [String] what changed: +/State/+, +/State/Light/+, +/State/Status/+ or +/Ident/+
      # @!attribute [r] content
      #   @return [Hash{String=>Object}] the new content of that resource
      Event = Data.define(:fab, :resource, :content)
    end
  end
end
