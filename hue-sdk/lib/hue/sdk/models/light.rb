# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A light service: on/off, dimming, color, gradient, effects.
      class Light < Base
        resource_type 'light'
        operations :update
        deprecated 'effects'
      end
    end
  end
end
