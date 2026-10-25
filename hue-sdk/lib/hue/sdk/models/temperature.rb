# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Temperature measured by a sensor.
      class Temperature < Base
        resource_type 'temperature'
        operations :update
      end
    end
  end
end
