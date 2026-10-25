# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # An entertainment area: the lights streamed together and their positions.
      class EntertainmentConfiguration < Base
        resource_type 'entertainment_configuration'
        operations :create, :update, :delete
      end
    end
  end
end
