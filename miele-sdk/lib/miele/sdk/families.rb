# frozen_string_literal: true

module Miele
  module Sdk
    # The class each appliance gets: the Miele app's family modules claim device types, on some protocols only.
    module Families
      # Family, device types, protocol versions, and the TechType some families also require.
      CLAIMS = [
        [Oven, [12, 13, 15, 31, 39, 45], [2, 3, 4], nil],
        [Hood, [18], [1, 2, 3, 4], nil],
        [Hob, [14, 27, 28], [1, 2, 4], nil],
        [Dishwasher, [7], [2, 3, 4], nil],
        [Dishwasher, [8], [2], /\APG81/],
        [WashingMachine, [1, 3, 24], [1, 2, 3, 4], nil],
        [TumbleDryer, [2, 4], [1, 2, 3, 4], nil],
        [CoffeeMaker, [17], [2, 3, 4], nil],
        [CoolingAppliance, [19, 20, 21, 32, 33, 34, 68], [0, 1, 200, 201, 203], nil],
        [WarmingDrawer, [25], [2], nil]
      ].freeze

      # @param ident [Schema::DeviceIdentification, nil]
      # @return [Class] the family's class, or {Appliance} for a type, a protocol (MACI) or a model no family takes
      # @api public
      def self.claim(ident)
        claim = CLAIMS.find { claims?(it, ident) } if ident
        claim ? claim.first : Appliance
      end

      def self.claims?(claim, ident)
        _, types, protocols, tech_type = claim
        types.include?(ident.device_type) && protocols.include?(ident.protocol_version) &&
          (tech_type.nil? || ident.device_ident_label&.tech_type.to_s.match?(tech_type))
      end
      private_class_method :claims?
    end
  end
end
