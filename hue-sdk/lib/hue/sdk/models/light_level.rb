# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Ambient light level measured by a sensor.
      class LightLevel < Base
        resource_type 'light_level'
        operations :update
      end
    end
  end
end
