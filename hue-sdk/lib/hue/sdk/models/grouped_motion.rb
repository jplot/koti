# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Motion aggregated over the sensors of a room or zone.
      class GroupedMotion < Base
        resource_type 'grouped_motion'
        operations :update
      end
    end
  end
end
