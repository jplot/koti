# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Motion sensed by lights in a MotionAware area, for convenience automations (Bridge Pro).
      class ConvenienceAreaMotion < Base
        resource_type 'convenience_area_motion'
        operations :update
      end
    end
  end
end
