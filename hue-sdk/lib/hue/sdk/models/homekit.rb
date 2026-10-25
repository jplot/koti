# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # HomeKit pairing state of the bridge.
      class Homekit < Base
        resource_type 'homekit'
        operations :update
      end
    end
  end
end
