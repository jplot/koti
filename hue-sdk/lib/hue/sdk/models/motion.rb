# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A motion sensor.
      class Motion < Base
        resource_type 'motion'
        operations :update
        deprecated 'motion.motion', 'motion.motion_valid'
      end
    end
  end
end
