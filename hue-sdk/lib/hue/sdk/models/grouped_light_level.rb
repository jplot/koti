# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Light level aggregated over the sensors of a room or zone.
      class GroupedLightLevel < Base
        resource_type 'grouped_light_level'
        operations :update
      end
    end
  end
end
