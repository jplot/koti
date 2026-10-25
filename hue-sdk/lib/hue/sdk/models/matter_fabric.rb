# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A Matter fabric (controller ecosystem) the bridge is shared with.
      class MatterFabric < Base
        resource_type 'matter_fabric'
        operations :update, :delete
      end
    end
  end
end
