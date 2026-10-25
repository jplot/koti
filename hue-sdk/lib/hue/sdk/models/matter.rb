# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Matter bridging state of the bridge.
      class Matter < Base
        resource_type 'matter'
        operations :update
      end
    end
  end
end
