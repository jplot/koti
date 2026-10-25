# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A behavior script available on the bridge: the template behavior instances are created from.
      class BehaviorScript < Base
        resource_type 'behavior_script'
        operations :update
      end
    end
  end
end
