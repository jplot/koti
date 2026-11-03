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

      # An automation to create. The app always names the types of the resource and of its metadata.
      class BehaviorInstanceAdd
        # @return [Hash{Symbol=>Object}] the value as a JSON body, without its nil members
        # @raise [ArgumentError] if a member the class requires is nil
        # @api public
        def to_body
          body = super
          body.merge(type: 'behavior_instance', metadata: { type: 'instance_metadata', **body.fetch(:metadata) })
        end
      end
    end
  end
end
