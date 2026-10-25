# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Zigbee search for new devices by the bridge.
      class ZigbeeDeviceDiscovery < Base
        resource_type 'zigbee_device_discovery'
        operations :update
      end
    end
  end
end
