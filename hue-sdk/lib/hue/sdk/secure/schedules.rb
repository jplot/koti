# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The schedules that arm and disarm a home, as the app's +ArmDisarmScheduleHttpClient+ reaches them. Never tested
      # on a device.
      class Schedules
        # @param home_id [String]
        # @api public
        def initialize(home_id)
          @path = "security/arm-manager/v1/home/#{home_id}/arm/schedules"
        end

        # @return [Array<Schema::ArmDisarmScheduleResponse>]
        # @raise (see Http.request)
        # @api public
        def list = Secure.client.get(@path).body.map { Schema::ArmDisarmScheduleResponse.from(it) }

        # @param request [Schema::CreateArmDisarmScheduleRequest]
        # @return [String] the id of the schedule
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def create(request)
          Schema::CreateArmDisarmScheduleResponse.from(Secure.client.post(@path, body: request).body).id
        end

        # @param id [String]
        # @param request [Schema::UpdateArmDisarmScheduleRequest]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def update(id, request) = Secure.client.put("#{@path}/#{id}", body: request)

        # @param id [String]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def delete(id) = Secure.client.delete("#{@path}/#{id}")
      end
    end
  end
end
