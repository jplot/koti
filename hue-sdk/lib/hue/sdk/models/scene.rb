# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A scene: a stored state for the lights of a room or zone, recalled by an action.
      class Scene < Base
        resource_type 'scene'
        operations :create, :update, :delete
      end
    end
  end
end
