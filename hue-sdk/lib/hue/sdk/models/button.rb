# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A button of a switch or remote, reporting presses as events.
      class Button < Base
        resource_type 'button'
        operations :update
        deprecated 'button.last_event'
      end
    end
  end
end
