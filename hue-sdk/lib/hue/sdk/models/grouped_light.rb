# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # The lights of a room, a zone or the whole home, switched together.
      class GroupedLight < Base
        resource_type 'grouped_light'
        operations :update
      end
    end
  end
end
