# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # A camera of a home, as the app's +CamerasHttpClient+ reaches it. Never tested on a device.
      class Camera
        PLAN = %i[subscribed experience_period].freeze
        ZONES = %w[activity_zones package_detection_zones lighting_zones].freeze
        private_constant :PLAN, :ZONES

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

        # @param request [Schema::CameraConfigUpdate]
        # @return [void]
        # @raise (see Http.request)
        # @api public
        def update(request) = Secure.client.put(@path, body: request)

        # As the app does, it refuses to turn clip recording on, or to change the activity, package or lighting zones,
        # unless the camera is +subscribed+ or in its +experience_period+, and it then reads the plans first. The app
        # lets a free-tier camera record clips kept 24 hours behind its remote toggle
        # +enable_24_hour_free_video_clips+; the toggle is off by default, and the gem follows the default.
        #
        # @param request [Schema::CameraCameraServiceUpdate]
        # @return [void]
        # @raise [ArgumentError] if the request leaves a required field nil; nothing is sent
        # @raise [PlanError] if the camera's status does not allow the change; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_camera(request)
          body = JSON.parse(JSON.generate(request))
          check_plan if body['clips_recording'] == true || ZONES.any? { body.key?(it) }
          Secure.client.put("#{@path}/service/camera/0", body: request)
        end

        # As the app does, it refuses to change sound detection unless the camera is +subscribed+ or in its
        # +experience_period+, and it then reads the plans first.
        #
        # @param request [Schema::CameraMicrophoneUpdate]
        # @return [void]
        # @raise [PlanError] if the camera's status does not allow the change; nothing is sent
        # @raise (see Http.request)
        # @api public
        def update_microphone(request)
          check_plan if JSON.parse(JSON.generate(request)).key?('smoke_alarm_detection')
          Secure.client.put("#{@path}/service/microphone/0", body: request)
        end

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

        # @return [void]
        # @raise [PlanError] unless the camera is subscribed or in its experience period
        # @api private
        def check_plan
          status = Plan.status(Secure.subscription, @id)
          raise PlanError.new(@id, status) unless PLAN.include?(status)
        end
      end
    end
  end
end
