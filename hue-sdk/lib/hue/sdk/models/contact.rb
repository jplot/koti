# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A contact sensor reporting whether a door or window is open.
      class Contact < Base
        resource_type 'contact'
        operations :update
      end
    end
  end
end
