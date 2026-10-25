# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # The rotary dial of a tap dial switch.
      class RelativeRotary < Base
        resource_type 'relative_rotary'
        operations :update
        deprecated 'relative_rotary.last_event'
      end
    end
  end
end
