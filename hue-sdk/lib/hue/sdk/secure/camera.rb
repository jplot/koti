# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # A camera of a home, as the app's +CamerasHttpClient+ reaches it. Never tested on a device.
      class Camera
        DETECTIONS = %w[people pet vehicle common_object].freeze
        private_constant :DETECTIONS

        # @return [String]
        attr_reader :id

        # @return [Hash{String=>Object}] what the cloud reported of it, as it came
        attr_reader :data

        # @param home_id [String]
        # @param id [String]
        # @param data [Hash{String=>Object}] what the cloud reported of it
        # @api public
        def initialize(home_id, id, data)
          @id = id
          @data = data
          @path = "security/device-configuration/v1/home/#{home_id}/device/#{id}"
          @speaker = "security/device-configuration/v2/home/#{home_id}/device/#{id}/service/speaker/0/command"
        end

        # The app reads a camera it cannot decode as a wired camera with what it could; the gem does not invent that
        # default, and {#data} keeps every key.
        #
        # @return [Schema::CameraResponse, nil] nil when the reported body does not have the shape of the app's class
        # @api public
        def attributes
          Schema::CameraResponse.from(@data)
        rescue TypeError
          nil
        end

        # What the app's alarm devices screen lets the alarm pick for this camera (_isSelectionOfDetectionTypeAllowed),
        # from its activity zones as the app converts them: none, or an empty list, allow all four; a single zone over
        # the entire area allows its own; several zones allow what any of them detects.
        #
        # @return [Array<String>, nil] among +people+, +pet+, +vehicle+ and +common_object+, in the app's order; nil
        #   when the app cannot convert the zones (a type it does not know, a zone without its area) and shows the
        #   camera no row
        # @api public
        def detections
          camera = attributes or return
          service = camera.service&.camera&.[]('0')
          allowed(Array(service&.activity_zones))
        end

        # @param request [Schema::CameraConfigUpdate]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def update(request) = Secure.client.put(@path, body: request)

        # @param request [Schema::CameraCameraServiceUpdate]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_camera(request) = Secure.client.put("#{@path}/service/camera/0", body: request)

        # @param request [Schema::CameraMicrophoneUpdate]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def update_microphone(request) = Secure.client.put("#{@path}/service/microphone/0", body: request)

        # @param service [String] the id of the speaker service
        # @param request [Schema::CameraSpeakerUpdate]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_speaker(service, request) = Secure.client.put("#{@path}/service/speaker/#{service}", body: request)

        # Chooses the chime or the automatic response of a doorbell, among {Secure.auto_responses}.
        #
        # @param service [String] the id of the bell button service
        # @param request [Schema::CameraBellButtonUpdate]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def update_bell_button(service, request)
          Secure.client.put("#{@path}/service/bell_button/#{service}", body: request)
        end

        # @param request [Schema::CameraMotionSensitivityUpdate]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_motion(request) = Secure.client.put("#{@path}/service/motion/0", body: request)

        # @param id [String] the device linked to the camera
        # @param request [Schema::CameraLinkedDeviceUpdate]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_linked_device(id, request) = Secure.client.put("#{@path}/linked_device/#{id}", body: request)

        # @return [void]
        # @raise (see Http.request)
        # @api public
        def snapshot = Secure.client.put("#{@path}/service/camera/0/command", body: { action_type: 'snapshot' })

        # @return [void]
        # @raise [ResponseError] with status 521 when the camera is out of reach
        # @raise (see Http.request)
        # @api public
        def wake_up = Secure.client.put("#{@path}/command", body: { action_type: 'wake_up' })

        # @return [void]
        # @raise (see Http.request)
        # @api public
        def reboot = Secure.client.put("#{@path}/command", body: { action_type: 'reboot' })

        # @return [void]
        # @raise (see Http.request)
        # @api public
        def reset = Secure.client.put("#{@path}/default_settings")

        # The app sends the volume, from 0.0 to 1.0, as a rounded number of hundredths, and none when it has none.
        #
        # @param sound [String]
        # @param volume [Float, nil] from 0.0 to 1.0
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def sound_chime(sound:, volume: nil)
          level = Schema::SpeakerCommandVolume.new(level: (volume * 100).round) if volume
          chime = Schema::SpeakerChimeCommand.new(sound:, volume: level)
          Secure.client.put(@speaker, body: Schema::SpeakerCommand.new(chime:))
        end

        # Sounds the siren for the 10 s the app sends.
        #
        # @return [void]
        # @raise [ResponseError] with status 521 when the camera is out of reach
        # @raise (see Http.request)
        # @api public
        def sound_alarm
          alarm = Schema::SpeakerAlarmCommand.new(sound: 'siren', duration: 10_000)
          Secure.client.put(@speaker, body: Schema::SpeakerCommand.new(alarm:))
        end

        private

        # convertResponseActivityZones.
        #
        # @param zones [Array<Schema::ActivityZoneResponse>]
        # @return [Array<String>, nil]
        # @api private
        def allowed(zones)
          return DETECTIONS if zones.empty?

          types = zones.map { it.detection_type.to_a }
          return unless (types.flatten - DETECTIONS).empty?
          return DETECTIONS & types.first if entire_area?(zones)

          DETECTIONS & types.flatten if zones.all?(&:area)
        end

        # @param zones [Array<Schema::ActivityZoneResponse>]
        # @return [Boolean] whether the zones are the app's entire video: one zone over the entire area
        # @api private
        def entire_area?(zones) = zones.one? && zones.first&.entire_area == true
      end
    end
  end
end
