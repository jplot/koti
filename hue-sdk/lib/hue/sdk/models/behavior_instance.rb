# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # An automation configured on the bridge (timer, wake-up, presence mimicking), instance of a behavior script.
      class BehaviorInstance < Base
        resource_type 'behavior_instance'
        operations :create, :update, :delete
      end
    end
  end
end
