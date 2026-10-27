# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Reads a resource of a known type as a typed value.
      module Typed
        # @return [Schema::Value] the resource built from {Base::Instance#data}, nested objects included
        #   (+Schema::Light+ for a light…); a deprecated field the SDK hides reads nil
        # @api public
        def attributes = Schema::RESPONSES.fetch(self.class.model.type).from(data)
      end
    end
  end
end
