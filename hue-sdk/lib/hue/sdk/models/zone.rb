# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A zone grouping lights across rooms.
      class Zone < Base
        resource_type 'zone'
        operations :create, :update, :delete
      end
    end
  end
end
