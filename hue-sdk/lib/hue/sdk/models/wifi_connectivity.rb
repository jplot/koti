# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Wi-Fi connectivity of the bridge or of a device.
      class WifiConnectivity < Base
        resource_type 'wifi_connectivity'
        operations :update
      end
    end
  end
end
