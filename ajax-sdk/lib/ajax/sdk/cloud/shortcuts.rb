# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # The LifeQuality history of a device: each measure by the start of its bucket, as the value the bucket
      # holds or the range it spans.
      LifeQualityHistory = Data.define(:temperature, :humidity, :co2) do
        # @param answer [Data] a +LifeQualityDataResponse+
        # @return [LifeQualityHistory]
        def self.from(answer)
          new(temperature: series(answer.values_temperature), humidity: series(answer.values_humidity),
              co2: series(answer.values_airquality))
        end

        # @api private
        def self.series(values) = values.to_h { |start, item| [Time.at(start, in: 'UTC'), bucket(item)] }

        # @api private
        def self.bucket(item)
          range = item.value_y_range
          range ? range.min_value_y..range.max_value_y : item.value_y
        end
        private_class_method :series, :bucket
      end

      # Everyday device and space actions, mixed into {Client}. Each one calls a method of {Methods}, so Steep
      # checks its request and read-only mode refuses its commands. A device the action does not fit raises
      # ArgumentError before anything is sent. Commands return nil, reads typed values.
      module Shortcuts
        SERVICE = Messages::Api::Ecosystem::V3::Mobilegwsvc::Service
        LOCATOR = Messages::Api::Ecosystem::V3::Mobilegwsvc::Commonmodels::Device::Locator
        HUBSVC = Messages::Api::Ecosystem::V2::Hubsvc::Commonmodels
        SPACE = Messages::Api::Mobile::V2::Common::Space
        private_constant :SERVICE, :LOCATOR, :HUBSVC, :SPACE

        # The devices, spaces and hubs the shortcuts address.
        module Targets
          private

          def hub_target(device) = { hub_id: hub_id_of(device), device_id: device.id }

          def hub_id_of(device) = device.hub_id || raise(ArgumentError, "#{device.kind} is not a device of the hub")

          def exact_type(device)
            HUBSVC::ObjectType.from(device.raw.dig(:hub_device, :common_device, :object_type) || {})
          end

          def family_type(family) = HUBSVC::ObjectType.from({ family => {} })

          def space_of(space_id) = SPACE::SpaceLocator.new(space_id:)

          def hub_of(space_id, hub_id)
            LOCATOR::DeviceLocator.new(space_id:, hub: LOCATOR::DeviceLocator::Hub.new(id: hub_id))
          end

          def first_of(stream) = stream.first || raise(ReadError, :refused)
        end

        # Relays, light switches, sockets, valves, dimmers, roller shutters and locks.
        module Outputs
          include Targets

          ROLLER = SERVICE::DeviceCommandRollerShutterControl
          # The app 3.59 switches a device by its family, never by its exact type.
          FAMILIES = { light_switch_channel: :light_switch, socket_base_channel: :socket_base,
                       water_stop_channel: :water_stop_base }.freeze
          private_constant :ROLLER, :FAMILIES

          # @param device [Device] a relay, light switch, socket or valve
          # @param channel [Integer] its channel or gang, from 1
          # @return [nil]
          # @raise [ArgumentError] for a device with nothing to switch, or without that channel
          def turn_on(device, channel: 1) = device_command_device_on(**switched(device, channel)).then { nil }

          # @param (see #turn_on)
          # @return [nil]
          # @raise (see #turn_on)
          def turn_off(device, channel: 1) = device_command_device_off(**switched(device, channel)).then { nil }

          # Sends the percentage as the app does: on the first channel, as a relative brightness.
          #
          # @param device [Device] a dimmer
          # @param percent [Integer] from 1 to 100
          # @return [nil]
          # @raise [ArgumentError] for another device or a percentage outside 1..100
          def set_brightness(device, percent)
            raise ArgumentError, "#{device.kind} is not a dimmer" unless device.kind == :light_switch_dimmer
            raise ArgumentError, "brightness #{percent} is outside 1..100" unless (1..100).cover?(percent)

            device_command_brightness(device_type: family_type(:light_switch_dimmer), brightness_in_percentage: percent,
                                      channels: [1], brightness_type: :relative, **hub_target(device))
            nil
          end

          # @param device [Device] a roller shutter
          # @return [nil]
          # @raise [ArgumentError] for another device
          def open_shutter(device) = move_shutter(device, 100)

          # @param (see #open_shutter)
          # @return [nil]
          # @raise (see #open_shutter)
          def close_shutter(device) = move_shutter(device, 0)

          # @param device [Device] a roller shutter
          # @param percent [Integer] the opening, from 0 (closed) to 100 (open)
          # @return [nil]
          # @raise [ArgumentError] for another device or an opening outside 0..100
          def move_shutter(device, percent)
            raise ArgumentError, "opening #{percent} is outside 0..100" unless (0..100).cover?(percent)

            goal = ROLLER::DeviceCommandRollerShutterControlRequest::TargetPosition
                   .new(shutter_target_position: percent)
            device_command_roller_shutter_control(**shutter(device), target_position: goal)
            nil
          end

          # @param (see #open_shutter)
          # @return [nil]
          # @raise (see #open_shutter)
          def stop_shutter(device)
            stop = ROLLER::DeviceCommandRollerShutterControlRequest::Stop.new
            device_command_roller_shutter_control(**shutter(device), stop:)
            nil
          end

          # @param device [Device] a lock of the hub or a cloud lock
          # @return [nil]
          # @raise [ArgumentError] for another device, such as a Yale lock of the hub
          def lock(device)
            return cloud_lock(device, :lock) unless hub_lock?(device)

            device_command_device_off(**hub_lock(device))
            nil
          end

          # @param (see #lock)
          # @return [nil]
          # @raise (see #lock)
          def unlock(device)
            return cloud_lock(device, :unlock) unless hub_lock?(device)

            device_command_device_on(**hub_lock(device))
            nil
          end

          # @param device [Device] a cloud lock
          # @return [nil]
          # @raise [ArgumentError] for another device: a lock of the hub cannot unlatch
          def unlatch(device) = cloud_lock(device, :unlatch)

          private

          def switched(device, channel)
            family = switch_family(device) or raise ArgumentError, "#{device.kind} has nothing to switch"
            unless family == :relay || device.channels.any? { it.number == channel }
              raise ArgumentError, "#{device.kind} has no channel #{channel}"
            end

            channels = family == :relay ? [] : [channel] #: Array[Integer]
            { hub_id: hub_id_of(device), device_id: device.id, device_type: family_type(family), channels: }
          end

          # Relays go by their kind, as the app's z221 dispatches them: a legacy relay sends no channel.
          def switch_family(device)
            found = (device.raw.dig(:hub_device, :spread_properties) || []).flat_map(&:keys)
            known = found.find { FAMILIES.key?(it) }
            return FAMILIES.fetch(known) if known

            case device.kind
            when :relay then :relay
            when :relay_fibra_base, :four_channels_relay_fibra then :relay_fibra_base
            else :transmitter_fibra_base if device.kind.start_with?('transmitter_fibra')
            end
          end

          def shutter(device)
            unless device.kind.start_with?('roller_shutter')
              raise ArgumentError, "#{device.kind} is not a roller shutter"
            end

            { hub_id: hub_id_of(device), device_id: device.id, device_type: exact_type(device) }
          end

          def hub_lock?(device) = device.kind == :smart_lock && !device.hub_id.nil?

          def hub_lock(device)
            { hub_id: hub_id_of(device), device_id: device.id, device_type: family_type(:smart_lock), channels: [1] }
          end

          def cloud_lock(device, action)
            raise ArgumentError, "#{device.kind} cannot #{action} through the cloud" unless device.kind == :smart_lock
            raise ArgumentError, "a lock of the hub cannot #{action}" unless device.hub_id.nil?

            switch_smart_lock(space_id: device.space_id, smart_lock_id: device.id, action:)
            nil
          end
        end

        # Bypasses, group arming, the security mode, the panic button and fire alarms.
        module Protection
          include Targets

          # @param device [Device] a device of the hub
          # @param tamper_only [Boolean] whether only its lid is bypassed
          # @param once [Boolean] whether the bypass ends at the next disarm, rather than lasting
          # @return [nil]
          # @raise [ArgumentError] for a device outside the hub
          def bypass(device, tamper_only: false, once: false)
            device_command_device_bypass(object_type: exact_type(device), bypass_type: bypass_kind(tamper_only, once),
                                         **hub_target(device))
            nil
          end

          # @param device [Device] a device of the hub
          # @param once [Boolean] whether it lifts a bypass that would end at the next disarm
          # @return [nil]
          # @raise [ArgumentError] for a device outside the hub
          def unbypass(device, once: false)
            device_command_device_bypass(
              object_type: exact_type(device), bypass_type: once ? :one_time_disable : :engineering_disable,
              **hub_target(device)
            )
            nil
          end

          # @param space_id [String]
          # @param group_id [String] a group of {Details#groups}
          # @param ignore_alarms [Boolean] whether it arms despite open detectors and malfunctions
          # @return [nil]
          def arm_group(space_id, group_id, ignore_alarms: false)
            space_security_arm_group(space_locator: space_of(space_id), group_id:, ignore_alarms:)
            nil
          end

          # @param (see #arm_group)
          # @return [nil]
          def disarm_group(space_id, group_id)
            space_security_disarm_group(space_locator: space_of(space_id), group_id:)
            nil
          end

          # @param space_id [String]
          # @param mode [Symbol] +:regular+, or +:group+ to arm and disarm by group
          # @return [nil]
          def set_security_mode(space_id, mode)
            space_security_set_security_mode(space_locator: space_of(space_id), mode:)
            nil
          end

          # Raises a real alarm.
          #
          # @param space_id [String]
          # @param location [Data, nil] a +PressPanicButtonRequest.Location+
          # @return [nil]
          def panic(space_id, location: nil)
            space_press_panic_button(space_locator: space_of(space_id), location:)
            nil
          end

          # @param device [Device] a fire detector with a mute command
          # @return [nil]
          # @raise [ArgumentError] for a device without one
          def mute(device)
            external = case device.mute_command
                       when :own then false
                       when :own_plus_external then true
                       else raise ArgumentError, "#{device.kind} has no mute command"
                       end
            device_command_sound_off(
              object_type: exact_type(device), mute_source_alarm: external ? %i[mute_own mute_external] : %i[mute_own],
              **hub_target(device)
            )
            nil
          end

          # @param hub_id [String]
          # @param except_triggered [Boolean] whether the detectors in alarm keep sounding
          # @return [nil]
          def mute_fire_detectors(hub_id, except_triggered: false)
            if except_triggered
              device_command_mute_all_fire_detectors_except_triggered(hub_id:)
            else
              device_command_mute_all_fire_detectors(hub_id:)
            end
            nil
          end

          # Only an EN54 hub resets a fire alarm through the cloud.
          #
          # @param hub_id [String]
          # @return [nil]
          def reset_fire_alarm(hub_id)
            hub_command_en54_hub_action(hub_id:, command_type: :reset_fire_alarm)
            nil
          end

          private

          def bypass_kind(tamper_only, once)
            return tamper_only ? :one_time_tamper : :one_time_sensor if once

            tamper_only ? :engineering_tamper : :engineering_sensor
          end
        end

        # Details and settings of devices and hubs, the scenarios, rooms and groups of a space, and LifeQuality
        # history.
        module Details
          include Targets

          # @param device [Device] a device of the hub
          # @return [Data, nil] its full +HubDevice+ model, with its settings
          # @raise [ArgumentError] for a device outside the hub
          # @raise [ReadError] when the gateway refuses the read
          def device_details(device)
            first_of(stream_hub_device(hub_id: hub_id_of(device), hub_device_id: device.id)).snapshot&.hub_device
          end

          # @param space_id [String]
          # @param hub_id [String]
          # @return [Data, nil] the +DeviceInfo+ of the hub: its parts, battery, connections and firmware
          # @raise [ReadError] when the gateway refuses the read
          def hub_details(space_id, hub_id)
            first_of(stream_device_info(device_locator: hub_of(space_id, hub_id))).snapshot&.device_info
          end

          # @param device [Device] a device of the hub
          # @param updates [Array<Data>] +Update+ values, one per changed part
          # @return [Data] the success, which may say the change waits for a press on the device
          # @raise [ArgumentError] for a device outside the hub
          def update_device_settings(device, *updates)
            update_hub_device(**hub_target(device), object_type: exact_type(device), update: updates)
          end

          # @param device [Device] a device of the hub
          # @param name [String]
          # @return (see #update_device_settings)
          # @raise (see #update_device_settings)
          def rename(device, name)
            settings = HUBSVC::Device::Common::DeviceProfile::DeviceProfileSettings.new(name:)
            update_device_settings(device, HUBSVC::Device::Update.new(device_profile_settings: settings))
          end

          # @param space_id [String]
          # @param hub_id [String]
          # @param updates [Array<Data>] +Update+ values, one per changed part
          # @return [Data] the success
          def update_hub_settings(space_id, hub_id, *updates)
            update_device(device_locator: hub_of(space_id, hub_id), update: updates)
          end

          # @param space_id [String]
          # @return [Array<Data>] its +LightScenario+ values
          # @raise [ReadError] when the gateway refuses the read
          def scenarios(space_id) = first_of(stream_light_scenarios(space_id:)).snapshot&.scenarios || []

          # @param space_id [String]
          # @param scenario_id [String] a scenario of {#scenarios}
          # @return [nil]
          def enable_scenario(space_id, scenario_id)
            set_scenario_state(space_id:, scenario_id:, enabled: true)
            nil
          end

          # @param (see #enable_scenario)
          # @return [nil]
          def disable_scenario(space_id, scenario_id)
            set_scenario_state(space_id:, scenario_id:, enabled: false)
            nil
          end

          # @param space_id [String]
          # @return [Array<Data>] its +Room+ values, each with an id and a name
          # @raise [ReadError] when the gateway refuses the read
          def rooms(space_id) = space_snapshot(space_id)&.rooms || []

          # @param space_id [String]
          # @return [Array<Data>] its security +Group+ values, each with an id and a name
          # @raise [ReadError] when the gateway refuses the read
          def groups(space_id) = space_snapshot(space_id)&.security&.groups || []

          # @param space_id [String]
          # @return [Data, nil] the signed-in account as a member of the space (+CurrentMember+): its role and
          #   permissions, which the app reads to show only the actions they allow
          # @raise [ReadError] when the gateway refuses the read
          def current_member(space_id) = space_snapshot(space_id)&.current_member

          # @param device [Device] a device with LifeQuality measures
          # @param from [Time]
          # @param to [Time]
          # @param step [Symbol] the width of a bucket: +:minute+, +:hour+, +:day+ or +:month+
          # @param time_zone [String] the IANA zone that sets where days and months start
          # @return [LifeQualityHistory]
          # @raise [ArgumentError] for a device without LifeQuality measures
          def life_quality_history(device, from:, to:, step: :hour, time_zone: 'UTC')
            raise ArgumentError, "#{device.kind} has no LifeQuality measures" unless device.life_quality

            zone = Messages::Google::Type::TimeZone.new(id: time_zone)
            LifeQualityHistory.from(
              life_quality_data_get_life_quality_data(hub_hex_id: hub_id_of(device), device_hex_id: device.id,
                                                      discreteness: step, time_zone: zone,
                                                      start_timestamp: from.to_i, end_timestamp: to.to_i)
            )
          end

          private

          def space_snapshot(space_id) = first_of(space_stream(space_locator: space_of(space_id))).snapshot
        end

        # The cameras and recorders of a space, and live WebRTC sessions with them.
        module Video
          include Targets

          STREAM_WEBRTC = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_webrtc.StreamWebrtcService/execute'
          REQUEST = SERVICE::StreamWebrtc::StreamWebrtcRequest
          FILTERS = Messages::Api::Mobile::V2::Common::Video::Webrtc::IceCandidateFilters
          private_constant :STREAM_WEBRTC, :REQUEST, :FILTERS

          # @param space_id [String]
          # @return [Array<VideoChannel>] every channel of the space's cameras and recorders, from the first message
          #   of +stream_video_player+
          # @raise [ReadError] when the gateway refuses the read
          def video_channels(space_id)
            video_edges = first_of(stream_video_player(space_id:)).initial_state&.video_edges || []
            video_edges.flat_map { |edge| edge.channels.map { VideoChannel.from(space_id, edge, it) } }
          end

          # Opens a WebRTC session with a camera or recorder, as the app does: its init lets every ICE candidate
          # through and starts the given streams. The session runs at {LiveVideo#each}.
          #
          # @param space_id [String]
          # @param video_edge_id [String] a {VideoChannel#video_edge_id}
          # @param streams [Array<Data>] the streams to start with, from {Streams}
          # @param allow_large_rtp_packets [Boolean] the app's setting, on unless its cloud configuration says not
          # @return [LiveVideo]
          def live_video(space_id, video_edge_id, streams, allow_large_rtp_packets: true)
            init = REQUEST::Init.new(space_locator: space_of(space_id), video_edge_id:, initial_streams: streams,
                                     ice_filters: every_candidate, allow_large_rtp_packets:)
            LiveVideo.new(exchange(STREAM_WEBRTC).write(REQUEST.new(init:)), streams)
          end

          private

          def every_candidate
            FILTERS.new(type_filter: FILTERS::TypeFilter.new(host: true, reflexive: true, relay: true),
                        protocol_filter: FILTERS::ProtocolFilter.new(tcp: true, udp: true))
          end
        end

        include Outputs
        include Protection
        include Details
        include Video
      end
    end
  end
end
