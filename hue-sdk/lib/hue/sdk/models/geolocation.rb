# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Geographic location of the bridge, used for sunrise and sunset.
      class Geolocation < Base
        resource_type 'geolocation'
        operations :update
      end
    end
  end
end
