# frozen_string_literal: true

module Hue
  module Sdk
    module Secure
      # The cameras of a home, as the app's +CamerasHttpClient+ lists them. Never tested on a device.
      class Cameras
        # @param home_id [String]
        # @api public
        def initialize(home_id)
          @home_id = home_id
          @path = "security/device-configuration/v1/home/#{home_id}/device"
        end

        # @return [Array<Camera>] every camera, a camera whose body the gem cannot read included
        # @raise (see Http.request)
        # @api public
        def list = Secure.client.get(@path).body.map { camera(it.fetch('reported')) }

        # @param id [String]
        # @return [Camera]
        # @raise [NotFoundError] for a camera the home does not have
        # @raise (see Http.request)
        # @api public
        def get(id) = Camera.new(@home_id, id, Secure.client.get("#{@path}/#{id}").body.fetch('reported'))

        # Sounds the speakers of the home together, as the app's alarm does, with no sound of their own.
        #
        # @param duration [Numeric] seconds
        # @return [void]
        # @raise [ResponseError] with status 207 when part of the speakers do not sound
        # @raise (see Http.request)
        # @api public
        def sound_group_alarm(duration:)
          alarm = Schema::SpeakerAlarmCommand.new(sound: 'no_sound', duration: (duration * 1000).to_i)
          Secure.client.put("security/device-configuration/v2/home/#{@home_id}/grouped_speaker/command",
                            body: Schema::SpeakerCommand.new(alarm:))
        end

        private

        # @param reported [Hash{String=>Object}]
        # @return [Camera]
        def camera(reported) = Camera.new(@home_id, reported['id'], reported)
      end
    end
  end
end
