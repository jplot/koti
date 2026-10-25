# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Firmware update state of a device.
      class DeviceSoftwareUpdate < Base
        resource_type 'device_software_update'
        operations :update
      end
    end
  end
end
