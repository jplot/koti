# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Read-only model for a resource type this version of the SDK does not
      # know, so that a newer bridge firmware never breaks associations or events.
      class Resource < Base
        # @param type [String] the unknown resource type
        # @return [Class] a read-only model bound to +type+, not registered
        # @api private
        def self.for(type)
          @generic ||= {} #: Hash[String, singleton(Resource)]
          @generic[type] ||= anonymous(type)
        end

        # @param type [String]
        # @return [Class] a new read-only model bound to +type+
        # @api private
        def self.anonymous(type)
          Class.new(self) { @type = type } #: singleton(Resource)
        end
      end
    end
  end
end
