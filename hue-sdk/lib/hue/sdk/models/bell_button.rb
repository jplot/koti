# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # The button of a Hue Secure video doorbell.
      class BellButton < Base
        resource_type 'bell_button'
        operations :update
        deprecated 'button.last_event'
      end
    end
  end
end
