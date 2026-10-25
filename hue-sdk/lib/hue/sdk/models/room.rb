# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A room grouping devices; lights are switched together through its grouped light.
      class Room < Base
        resource_type 'room'
        operations :create, :update, :delete
      end
    end
  end
end
