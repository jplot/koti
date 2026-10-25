# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Power output mode of a device that controls the power of its connected lights.
      class PowerOutputConfiguration < Base
        resource_type 'power_output_configuration'
        operations :update
      end
    end
  end
end
