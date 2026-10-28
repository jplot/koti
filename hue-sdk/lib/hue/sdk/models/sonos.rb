# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # The Sonos service of the bridge: it lists the actions it accepts, and an update sends one.
      class Sonos < Base
        resource_type 'sonos'
        operations :update
      end
    end
  end
end
