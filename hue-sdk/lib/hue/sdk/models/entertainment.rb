# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Entertainment capabilities of a light: channels, segments and proxy role.
      class Entertainment < Base
        resource_type 'entertainment'
        operations :update
      end
    end
  end
end
