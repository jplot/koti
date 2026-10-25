# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Battery state of a battery-powered device (read-only).
      class DevicePower < Base
        resource_type 'device_power'
      end
    end
  end
end
