# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Motion sensed by lights in a MotionAware area, for security use (Bridge Pro).
      class SecurityAreaMotion < Base
        resource_type 'security_area_motion'
        operations :update
      end
    end
  end
end
