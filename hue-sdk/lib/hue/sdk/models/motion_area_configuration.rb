# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Configuration of a MotionAware motion area (Bridge Pro).
      class MotionAreaConfiguration < Base
        resource_type 'motion_area_configuration'
        operations :create, :update, :delete
      end
    end
  end
end
