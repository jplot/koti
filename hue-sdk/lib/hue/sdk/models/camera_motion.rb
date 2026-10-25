# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Motion detection of a Hue Secure camera.
      class CameraMotion < Base
        resource_type 'camera_motion'
        operations :update
      end
    end
  end
end
