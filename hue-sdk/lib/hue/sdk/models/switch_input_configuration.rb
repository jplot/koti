# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Input configuration of a wall switch module (switch mode).
      class SwitchInputConfiguration < Base
        resource_type 'switch_input_configuration'
        operations :update
      end
    end
  end
end
