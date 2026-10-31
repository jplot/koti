# frozen_string_literal: true

module Miele
  module Sdk
    # Live state changes pushed by the appliances of the household.
    module Events
      # Device type this host takes as a peer: the Miele panels do not list it.
      DEVICE_TYPE = 2_147_483_647

      # Steep types a method of a Data.define block as one of the enclosing module, hence the reopened class.
      Event = Data.define(:fab, :resource, :content, :source)

      # A change an appliance pushed, to this host or through the Miele cloud.
      #
      # @!attribute [r] fab
      #   @return [String, nil] fabrication number of the appliance that pushed it, or the cloud's +mac-…+ id;
      #     nil for the list of devices
      # @!attribute [r] resource
      #   @return [String] what changed: +/State/+, +/State/Light/+, +/State/Status/+ or +/Ident/+; through the
      #     cloud also +/DOP2/{unit}/{attribute}/+ and +/Devices/+
      # @!attribute [r] content
      #   @return [Hash{String=>Object}, Dop2::Leaf, Array<Hash{String=>Object}>] the new content of that resource
      # @!attribute [r] source
      #   @return [Symbol] +:local+ for an appliance's push, +:cloud+ for the websocket's
      class Event
        # @param fab [String, nil]
        # @param resource [String]
        # @param content [Object]
        # @param source [Symbol]
        def initialize(fab:, resource:, content:, source: :local) = super
        # @return [Schema::DeviceIdentification, Schema::DeviceState] {#content} as a typed value: the
        #   identification for +/Ident/+, else the state, of which +/State/Light/+ and +/State/Status/+
        #   push only +Light+ or +Status+
        # @api public
        def attributes = (resource == '/Ident/' ? Schema::DeviceIdentification : Schema::DeviceState).from(content)
      end
    end
  end
end
