# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Lights that can form a MotionAware area (Bridge Pro).
      class MotionAreaCandidate < Base
        resource_type 'motion_area_candidate'
        operations :update
      end
    end
  end
end
