# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A motion sensor.
      class Motion < Base
        resource_type 'motion'
        operations :update
      end
    end
  end
end
