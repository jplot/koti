# frozen_string_literal: true

module Hue
  module Sdk
    module Schema
      # Reads a configuration with the class of its script, when the JSON gives the script: an automation does, and the
      # event that adds one. The bridge does not describe these forms.
      module TypedConfiguration
        # Builds the value from the JSON of the bridge.
        #
        # @param data [Hash{String=>Object}]
        # @return [Value]
        # @api public
        def from(data)
          value = super #: untyped
          value.with(configuration: read_configuration(value.script_id, value.configuration))
        end

        private

        # The app keeps as it is the JSON it cannot decode (BridgeBehavior._decodeAccessoryConfiguration): a
        # configuration its class would not send back whole stays a hash.
        #
        # @param script_id [String, nil]
        # @param data [Object]
        # @return [Value, Object]
        # @api private
        def read_configuration(script_id, data)
          typed = Value.load(BEHAVIOR_CONFIGURATIONS[script_id], data)
          JSON.parse(JSON.generate(typed)) == data ? typed : data
        rescue ArgumentError, NoMethodError, TypeError
          data
        end
      end

      # An automation of the bridge.
      class BehaviorInstance
        extend TypedConfiguration
      end

      # The changes of an automation, as an event reports them.
      class BehaviorInstanceChange
        extend TypedConfiguration
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
