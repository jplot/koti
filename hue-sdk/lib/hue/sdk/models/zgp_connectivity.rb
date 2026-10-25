# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Zigbee Green Power connectivity of a battery-free switch.
      class ZgpConnectivity < Base
        resource_type 'zgp_connectivity'
        operations :update
      end
    end
  end
end
