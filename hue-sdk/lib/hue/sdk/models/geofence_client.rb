# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # A geofencing client (a phone) telling the bridge whether someone is at home.
      class GeofenceClient < Base
        resource_type 'geofence_client'
        operations :create, :update, :delete
      end
    end
  end
end
