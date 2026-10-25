# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A speaker (chime, siren) of a Hue Secure device.
      class Speaker < Base
        resource_type 'speaker'
        operations :update
      end
    end
  end
end
