# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A physical device (bulb, switch, sensor, bridge) and the services it offers.
      class Device < Base
        resource_type 'device'
        operations :update, :delete
        deprecated 'device_mode'
      end
    end
  end
end
