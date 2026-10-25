# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Tamper detection of a sensor.
      class Tamper < Base
        resource_type 'tamper'
        operations :update
      end
    end
  end
end
