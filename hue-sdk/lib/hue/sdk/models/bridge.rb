# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # The bridge itself: identity and time zone.
      class Bridge < Base
        resource_type 'bridge'
        operations :update
      end
    end
  end
end
