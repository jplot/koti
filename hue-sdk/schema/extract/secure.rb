# frozen_string_literal: true

require_relative 'behaviors'
require_relative 'requests'

module Schema
  module Extract
    # The Hue Secure classes some roots reach, which json_serializable writes in the app: a response is read from its
    # fromJson, as an automation's class is, and a request, which has none, from the keys its toJson writes.
    class SecureClasses < BehaviorClasses
      # What the load of a field tells of its value. A pointer may hold anything, which Value.dump sends as it is.
      TYPES = { 'int' => 'Integer', 'double' => 'Numeric', 'bool' => 'Boolean' }.freeze

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

      # The keys an automation's fromJson drops are the defaults of its type; a Hue Secure class reads them, as
      # AlarmSignal does +speaker+.
      def decoded(origin)
        address, size = @snapshot.function("._$#{origin}FromJson")
        CheckedFromJson.new(@snapshot).decoded(address, size) ||
          BehaviorFromJson.new(@snapshot, origin, dropped: []).decoded(@snapshot.instructions(address, size))
      end

      def name(origin)
        raise ArgumentError, "#{origin} is in another generated file" if @taken.include?(origin)

        origin
      end
    end

    # A fromJson json_serializable writes with +checked: true+, which hands $checkedCreate a closure converting each
    # key through a closure of its own. The type arguments of each conversion give the Dart type of the field, and the
    # first cast of its closure whether the key may be missing: a default the app gives a null key makes it nullable.
    class CheckedFromJson
      CREATE = '.$checkedCreate<Y0>'
      CLOSURE = /\AAnonymousClosure: static \(0x(\h+)\)/
      ARGUMENTS = /\ATypeArguments: <(.+)>\z/
      KEY = /\AString: "(.*)"\z/
      CAST = /\AType: (.+)\z/

      def initialize(snapshot) = @snapshot = snapshot

      # @return [Hash{String=>Hash}, nil] by key, the field as BehaviorFromJson describes it; nil when the fromJson at
      #   that address is not checked
      def decoded(address, size)
        code = @snapshot.instructions(address, size)
        return unless code.any? { (target = it[/\Abl\s+0x(\h+)/, 1]) && @snapshot.owner(target.hex) == CREATE }

        fields(body(objects(code).filter_map { it[CLOSURE, 1] }.first.hex))
      end

      private

      def fields(code)
        seen = {}
        pages = {}
        code.each_with_object({}) do |instruction, fields|
          if instruction.match?(/\Ablr\s+x2\z/)
            fields[seen[:key]] = field(seen[:arguments].to_s, seen[:closure]) if seen[:key]
            seen.clear
          else
            remember(seen, object(instruction, pages))
          end
        end
      end

      def remember(seen, object)
        return unless object

        seen[:closure] = object[CLOSURE, 1].hex if object.match?(CLOSURE)
        seen[:arguments] = object[ARGUMENTS, 1] if object.match?(ARGUMENTS)
        seen[:key] = object[KEY, 1] if object.match?(KEY)
      end

      # A null check before the cast is a default the app gives a missing key, as CameraResponse.metadata has.
      def field(dart, closure)
        code = body(closure)
        cast, at = first_cast(code)
        checked = code.take(at).any? { it.match?(/\Acmp\s+w\d+, w22\z/) }
        describe(dart).merge('reads' => 1, 'optional' => cast.nil? || cast.end_with?('?') || checked)
      end

      def first_cast(code)
        pages = {}
        code.each_with_index do |instruction, index|
          cast = object(instruction, pages).to_s[CAST, 1]
          return [cast, index] if cast
        end
        [nil, code.size]
      end

      def describe(dart)
        base = dart.delete_suffix('?')
        return container(dart, base) if container(dart, base)
        return { 'type' => dart, 'enum' => base } if @snapshot.enum_values(base)

        readable?(base) ? { 'type' => dart, 'class' => base } : { 'type' => dart }
      end

      def container(dart, base)
        inner = base[/\A(?:Map<String, |List<)(\w+)>\z/, 1]
        list = base.start_with?('List<')
        return unless inner && (readable?(inner) || (list && Types.primitive(inner)))

        { 'type' => dart, (list ? 'items' : 'map') => inner }
      end

      def readable?(dart) = !@snapshot.function("._$#{dart}FromJson").nil? || !@snapshot.enum_values(dart).nil?

      def body(address)
        code = @snapshot.instructions(address, 0x2000)
        code.take(code.index { it.start_with?('ret') } || code.size)
      end

      def objects(code)
        pages = {}
        code.filter_map { object(it, pages) }
      end

      def object(instruction, pages)
        case instruction
        when /\Aadd\s+(x\d+), x27, #0x(\h+), lsl #12\z/
          pages[Regexp.last_match(1)] = Regexp.last_match(2).hex << 12
          nil
        when /\Aldr\s+x\d+, \[x27, #0x(\h+)\]\z/ then @snapshot.object(Regexp.last_match(1).hex).to_s
        when /\Aldr\s+x\d+, \[(x\d+), #0x(\h+)\]\z/
          page = pages.delete(Regexp.last_match(1))
          @snapshot.object(page + Regexp.last_match(2).hex).to_s if page
        end
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
                    FetchGeofenceClientResponse UpdateGeofenceClientRequest],
        'cameras' => %w[CameraResponse CameraConfigUpdate CameraConfigMetadataUpdate CameraLinkedDeviceUpdate
                        CameraLinkedDeviceMetadataUpdate CameraCameraServiceUpdate ActivityZoneUpdate PrivacyZoneUpdate
                        PackageDetectionZoneUpdate LightingZoneUpdate DetectionZonePointUpdate CameraMicrophoneUpdate
                        CameraSmokeAlarmDetectionUpdate CameraSpeakerUpdate CameraSpeakerMuteUpdate
                        CameraBellButtonUpdate CameraBellButtonChimeSoundUpdate CameraBellButtonAutomaticResponseUpdate
                        CameraMotionSensitivityUpdate SpeakerCommand SpeakerChimeCommand SpeakerAlarmCommand
                        SpeakerCommandVolume FetchedAutoResponseConfiguration],
        'events' => %w[MessageEventMetaData MessageEventTraceInfo ActionAllSafeEvent ArmEvent TriggerEvent GeofenceEvent
                       MotionClipV2Event BatteryClipV2Event ContactClipV2Event TamperClipV2Event
                       ZigbeeConnectivityClipV2Event MotionAreaClipV2Event MotionAreaConfigurationClipV2Event
                       MotionCameraEvent ClipsUploadCameraEvent WifiConnectivityCameraEvent BatteryCameraEvent
                       AudioDetectionCameraEvent DoorbellButtonCameraEvent DeviceRemovedEvent BridgeConnectivityEvent
                       DeleteTimelineEntriesEvent PurgeTimelineEvent RefreshTimelineEvent ReportTimelineEntriesEvent
                       SecurityEventInsightsResponse TimelineEventsDelete TimelineEventDelete TimelineEventsReport
                       TimelineEventReport AllSafeRequest AlarmTriggerRequest]
      }.freeze
    end
  end
end
