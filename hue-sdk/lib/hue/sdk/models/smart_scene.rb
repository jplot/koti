# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A scene whose state follows the time of day.
      class SmartScene < Base
        resource_type 'smart_scene'
        operations :create, :update, :delete
      end
    end
  end
end
