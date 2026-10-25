# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A group of services of the same kind, combined into one.
      class ServiceGroup < Base
        resource_type 'service_group'
        operations :update
      end
    end
  end
end
