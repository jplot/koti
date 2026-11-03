# frozen_string_literal: true

module Hue
  module Sdk
    module Schema
      # An automation of the bridge. Its configuration has a form per script, which the bridge does not describe.
      class BehaviorInstance
        # Builds the value from the JSON of the bridge, its configuration typed when the SDK knows its script.
        #
        # @param data [Hash{String=>Object}]
        # @return [BehaviorInstance]
        # @api public
        def self.from(data)
          value = super #: BehaviorInstance
          value.with(configuration: Value.load(BEHAVIOR_CONFIGURATIONS[value.script_id], value.configuration))
        end
      end
    end
  end
end
