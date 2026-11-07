# frozen_string_literal: true

require_relative 'behaviors'
require_relative 'requests'

module Schema
  module Extract
    # The Hue Secure classes some roots reach, which json_serializable writes in the app: a response is read from its
    # fromJson, as an automation's class is, and a request, which has none, from the keys its toJson writes.
    class SecureClasses < BehaviorClasses
      # What the load of a field tells of its value. A pointer may hold anything, which Value.dump sends as it is.
      TYPES = { 'int' => 'Integer', 'double' => 'Numeric', 'string' => 'String' }.freeze

      # @param roots [Array<String>] classes of the app
      # @return [Hash{String=>Hash}] the classes by name
      # @raise [ArgumentError] for a class another generated file holds, or one with neither fromJson nor toJson
      def read(roots)
        queue = roots.dup
        queue.each_with_object({}) do |origin, classes|
          next if classes.key?(origin)

          classes[name(origin)] = @snapshot.function("._$#{origin}FromJson") ? response(origin, queue) : request(origin)
        end
      end

      private

      def response(origin, queue)
        decoded = decoded(origin)
        queue.concat(decoded.values.filter_map { held(it) })
        { 'origin' => origin, 'kind' => 'response', 'fields' => decoded.transform_values { field(it) } }
      end

      def request(origin)
        written = Requests.new(@snapshot, {}).written(origin)
        raise ArgumentError, "no fromJson nor toJson for #{origin}" unless written

        fields = written.transform_values do |field|
          { 'type' => TYPES.fetch(field['kind'], 'Object'), 'required' => field['required'] }
        end
        { 'origin' => origin, 'kind' => 'request', 'fields' => fields }
      end

      def name(origin)
        raise ArgumentError, "#{origin} is in another generated file" if @taken.include?(origin)

        origin
      end
    end

    # The roots of each generated file of Hue Secure, as the paths of its clients give them. A request's toJson does
    # not name the classes it holds, so each request class is a root. SetAlarmStateRequest is not one: its toJson
    # writes the one constant the app sends.
    module SecureSchema
      ROOTS = {
        'arm' => %w[ArmDisarmResponse ArmDisarmStateResponse ArmDisarmSetStateRequest ArmDisarmSetConfigRequest
                    ArmDisarmModeConfigRequest ArmDisarmDeviceConfigRequest ArmDisarmGeofenceConfigChangeRequest
                    ArmDisarmGeofenceStatusConfigRequest ArmDisarmScheduleConfigChangeRequest ArmDisarmScheduleResponse
                    CreateArmDisarmScheduleResponse CreateArmDisarmScheduleRequest UpdateArmDisarmScheduleRequest
                    ArmDisarmScheduleConfigurationRequest ArmDisarmScheduleActionInfoRequest
                    FetchGeofenceClientResponse UpdateGeofenceClientRequest]
      }.freeze
    end
  end
end
