# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Zigbee connectivity of a device.
      class ZigbeeConnectivity < Base
        resource_type 'zigbee_connectivity'
        operations :update
      end
    end
  end
end
