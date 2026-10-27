# frozen_string_literal: true

module Hue
  module Sdk
    # Models of the CLIP v2 resources, one class per resource type.
    module Models
      # Model class of every known resource type, keyed by type.
      REGISTRY = {} # rubocop:disable Style/MutableConstant -- filled by Base.resource_type, frozen once every model is loaded

      # @param type [String] CLIP v2 resource type
      # @return [Class] the registered model, or a read-only generic one for a type this version does not know
      # @api public
      def self.lookup(type) = REGISTRY.fetch(type) { Resource.for(type) }
    end
  end
end

require_relative 'models/operations'
require_relative 'models/typed'
require_relative 'models/base'
require_relative 'models/resource'
Dir[File.join(File.dirname(__FILE__), 'models', '*.rb')].each { |model| require model }
Hue::Sdk::Models::REGISTRY.freeze
