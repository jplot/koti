# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Shortcuts do
  let(:client) { Ajax::Sdk::Cloud::Client.new(settings) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'gw', grpc_port: 443, read_timeout: 30,
                                                        ca_file: nil, read_only: false, session_token: 'tok',
                                                        user_id: 'uid')
  end

  def device(kind, *spread, hub: true)
    light = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V3::Mobilegwsvc::Commonmodels::Space::Device::Light
    common = { profile: { id: '0000BEEF' }, hub_id: '0000ABCD', object_type: { kind => {} } }
    item = { kind => { profile: { id: '0000BEEF' }, spread_properties: spread } }
    item = { hub_device: { common_device: common, spread_properties: spread } } if hub
    Ajax::Sdk::Cloud::Device.from(light::LightDeviceItem.from(item), space_id: 'space-1')
  end

  def channel_id(number) = :"CHANNEL_ID_#{number}"

  def gang(number) = { light_switch_channel: { id: channel_id(number) } }

  def mute_button(command) = { fire_device_action_button: { mute_button: { mute_command: command } } }

  def target = { hub_id: '0000ABCD', device_id: '0000BEEF' }

  def camera
    Ajax::Sdk::Cloud::VideoChannel.new(space_id: 'space-1', video_edge_id: '0000ABCD', channel_id: 'ch-1', ptz: false,
                                       sub_stream: true, sound: true, raw: nil)
  end

  def camera_target = { space_id: 'space-1', video_edge_id: '0000ABCD', channel_id: 'ch-1' }

  def gw = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V3::Mobilegwsvc::Service

  def fire = device(:fire_protect_two, mute_button(:MUTE_COMMAND_OWN))

  def error_of
    yield
    nil
  rescue StandardError => e
    e.class
  end

  it 'clashes with no other method of the client' do
    owners = [Ajax::Sdk::Cloud::Client, Ajax::Sdk::Cloud::Resources, Ajax::Sdk::Cloud::Methods]
    taken = owners.flat_map { it.instance_methods(false) + it.private_instance_methods(false) } +
            Object.instance_methods + Object.private_instance_methods

    expect((described_class.instance_methods + described_class.private_instance_methods) & taken).to be_empty
  end

  context 'with call doubled' do
    let(:sent) { [] }

    def replying(value)
      allow(client).to receive(:call) do |path, request|
        sent << [path.split('.').last, request.to_message]
        value
      end
    end

    before { replying(nil) }

    it 'turns on the second gang of a light switch with the family type' do
      client.turn_on(device(:light_switch_two_gang, gang(1), gang(2)), channel: 2)

      expect(sent).to eq([['DeviceCommandDeviceOnService/execute',
                           { **target, device_type: { light_switch: {} }, channels: [2] }]])
    end

    it 'switches a socket, a valve and a Fibra transmitter with their family types' do
      client.turn_off(device(:socket_g, { socket_base_channel: { id: channel_id(1) } }))
      client.turn_off(device(:water_stop, { water_stop_channel: { id: channel_id(1) } }))
      client.turn_off(device(:transmitter_fibra_two_channels, { channel: { channel_id: 1 } }))

      expect(sent.map { it.last[:device_type] })
        .to eq([{ socket_base: {} }, { water_stop_base: {} }, { transmitter_fibra_base: {} }])
    end

    it 'turns a legacy relay on without a channel, even one that reports a channel' do
      client.turn_on(device(:relay))
      client.turn_on(device(:relay, { channel: { channel_id: 1 } }))

      expect(sent.map(&:last)).to all(eq({ **target, device_type: { relay: {} }, channels: [] }))
    end

    it 'switches a Fibra relay by its base type and its channel' do
      relay = device(:four_channels_relay_fibra, { channel: { channel_id: 1 } }, { channel: { channel_id: 3 } })
      client.turn_off(relay, channel: 3)

      expect(sent).to eq([['DeviceCommandDeviceOffService/execute',
                           { **target, device_type: { relay_fibra_base: {} }, channels: [3] }]])
    end

    it 'refuses a channelled device whose on and off flow the app does not show' do
      expect { client.turn_on(device(:wall_switch, { channel: { channel_id: 1 } })) }
        .to raise_error(ArgumentError, /wall_switch/)
    end

    it 'refuses to switch a device with no switchable channel, or a channel it does not have', :aggregate_failures do
      expect { client.turn_on(device(:door_protect)) }.to raise_error(ArgumentError, /door_protect/)
      expect { client.turn_on(device(:light_switch_one_gang, gang(1)), channel: 2) }.to raise_error(ArgumentError, /2/)
      expect(client).not_to have_received(:call)
    end

    it 'sets a dimmer brightness the way the app does' do
      client.set_brightness(device(:light_switch_dimmer, gang(1)), 40)

      expect(sent.last.last).to eq({ **target, device_type: { light_switch_dimmer: {} }, brightness_in_percentage: 40,
                                               channels: [1], brightness_type: :BRIGHTNESS_TYPE_RELATIVE })
    end

    it 'refuses a brightness outside 1 to 100, or a device that is not a dimmer', :aggregate_failures do
      dimmer = device(:light_switch_dimmer, gang(1))

      expect([0, 101].map { |percent| error_of { client.set_brightness(dimmer, percent) } }).to eq([ArgumentError] * 2)
      expect { client.set_brightness(device(:relay), 50) }.to raise_error(ArgumentError, /relay/)
      expect(client).not_to have_received(:call)
    end

    it 'opens a shutter to 100 and stops it' do
      shutter = device(:roller_shutter_ls)
      client.open_shutter(shutter)
      client.stop_shutter(shutter)

      expect(sent.map(&:last)).to eq([{ **target, device_type: { roller_shutter_ls: {} },
                                                  target_position: { shutter_target_position: 100 } },
                                      { **target, device_type: { roller_shutter_ls: {} }, stop: {} }])
    end

    it 'closes a shutter and moves it to an opening' do
      client.close_shutter(device(:roller_shutter_ws))
      client.move_shutter(device(:roller_shutter_ws), 30)

      expect(sent.map { it.last[:target_position] })
        .to eq([{ shutter_target_position: 0 }, { shutter_target_position: 30 }])
    end

    it 'refuses a shutter opening outside 0 to 100, or a device that is not a shutter', :aggregate_failures do
      expect { client.move_shutter(device(:roller_shutter_ws), 101) }.to raise_error(ArgumentError, /101/)
      expect { client.close_shutter(device(:door_protect)) }.to raise_error(ArgumentError, /door_protect/)
      expect(client).not_to have_received(:call)
    end

    it 'bypasses the lid only, once, then lifts a permanent bypass' do
      detector = device(:door_protect_plus)
      client.bypass(detector, tamper_only: true, once: true)
      client.unbypass(detector)

      expect(sent.map { it.last.values_at(:object_type, :bypass_type) })
        .to eq([[{ door_protect_plus: {} }, :BYPASS_ONE_TIME_TAMPER],
                [{ door_protect_plus: {} }, :BYPASS_ENGINEERING_DISABLE]])
    end

    it 'arms a group without overriding alarms by default, and disarms it' do
      client.arm_group('space-1', 'g1')
      client.disarm_group('space-1', 'g1')

      expect(sent).to eq([['SpaceSecurityService/armGroup',
                           { space_locator: { space_id: 'space-1' }, group_id: 'g1', ignore_alarms: false }],
                          ['SpaceSecurityService/disarmGroup',
                           { space_locator: { space_id: 'space-1' }, group_id: 'g1' }]])
    end

    it 'bypasses a whole detector or its lid, lasting or once, and lifts a one-time bypass' do
      detector = device(:door_protect_plus)
      client.bypass(detector)
      client.bypass(detector, tamper_only: true)
      client.bypass(detector, once: true)
      client.unbypass(detector, once: true)

      expect(sent.map { it.last[:bypass_type] })
        .to eq(%i[BYPASS_ENGINEERING_SENSOR BYPASS_ENGINEERING_TAMPER BYPASS_ONE_TIME_SENSOR BYPASS_ONE_TIME_DISABLE])
    end

    it 'arms a group overriding alarms, and sets the group security mode' do
      client.arm_group('space-1', 'g1', ignore_alarms: true)
      client.set_security_mode('space-1', :group)

      expect(sent).to eq([['SpaceSecurityService/armGroup',
                           { space_locator: { space_id: 'space-1' }, group_id: 'g1', ignore_alarms: true }],
                          ['SpaceSecurityService/setSecurityMode',
                           { space_locator: { space_id: 'space-1' }, mode: :GROUP }]])
    end

    it 'locks a jeweller lock with device_off' do
      client.lock(device(:smart_lock, { smart_lock_control: { state: :LOCK_STATE_UNLOCKED } }))

      expect(sent).to eq([['DeviceCommandDeviceOffService/execute',
                           { **target, device_type: { smart_lock: {} }, channels: [1] }]])
    end

    it 'unlocks a jeweller lock with device_on, and locks and unlocks a cloud lock' do
      cloud = device(:smart_lock, hub: false)
      client.unlock(device(:smart_lock))
      client.lock(cloud)
      client.unlock(cloud)

      expect(sent.map { [it.first, it.last[:action]] })
        .to eq([['DeviceCommandDeviceOnService/execute', nil], ['SwitchSmartLockService/execute', :ACTION_LOCK],
                ['SwitchSmartLockService/execute', :ACTION_UNLOCK]])
    end

    it 'unlatches a cloud lock' do
      client.unlatch(device(:smart_lock, { smart_lock_control: { state: :LOCK_STATE_LOCKED } }, hub: false))

      expect(sent).to eq([['SwitchSmartLockService/execute',
                           { space_id: 'space-1', smart_lock_id: '0000BEEF', action: :ACTION_UNLATCH }]])
    end

    it 'refuses to unlatch a jeweller lock, and any Yale lock', :aggregate_failures do
      expect { client.unlatch(device(:smart_lock)) }.to raise_error(ArgumentError, /unlatch/)
      expect { client.lock(device(:smart_lock_yale)) }.to raise_error(ArgumentError, /smart_lock_yale/)
      expect(client).not_to have_received(:call)
    end

    it 'mutes own and external alarms' do
      client.mute(device(:fire_protect_two, mute_button(:MUTE_COMMAND_OWN_PLUS_EXTERNAL)))

      expect(sent.last.last[:mute_source_alarm]).to eq(%i[MUTE_SOURCE_ALARM_MUTE_OWN MUTE_SOURCE_ALARM_MUTE_EXTERNAL])
    end

    it 'mutes only its own alarm, and every fire detector of a hub' do
      client.mute(fire)
      client.mute_fire_detectors('0000ABCD')

      expect(sent).to eq([['DeviceCommandSoundOffService/execute',
                           { object_type: { fire_protect_two: {} }, mute_source_alarm: [:MUTE_SOURCE_ALARM_MUTE_OWN],
                             **target }],
                          ['DeviceCommandMuteAllFireDetectorsService/execute', { hub_id: '0000ABCD' }]])
    end

    it 'refuses to mute a device without a mute command' do
      expect { client.mute(device(:door_protect)) }.to raise_error(ArgumentError, /mute/)
    end

    it 'mutes the fire detectors but the triggered ones, and resets an EN54 fire alarm' do
      client.mute_fire_detectors('0000ABCD', except_triggered: true)
      client.reset_fire_alarm('0000ABCD')

      expect(sent).to eq([['DeviceCommandMuteAllFireDetectorsExceptTriggeredService/execute', { hub_id: '0000ABCD' }],
                          ['HubCommandEn54HubActionService/execute',
                           { hub_id: '0000ABCD', command_type: :COMMAND_TYPE_RESET_FIRE_ALARM }]])
    end

    it 'presses the panic button of a space' do
      client.panic('space-1')

      expect(sent).to eq([['SpaceService/pressPanicButton', { space_locator: { space_id: 'space-1' } }]])
    end

    it 'returns nil from a command' do
      replying(gw::DeviceCommandDeviceOn::DeviceCommandDeviceOnResponse.from({ success: {} }))

      expect(client.disarm_group('space-1', 'g1')).to be_nil
    end

    it 'reads the full model of a device', :aggregate_failures do
      snapshot = { snapshot: { hub_device: { door_protect: {} } } }
      replying([gw::StreamHubDevice::StreamHubDeviceResponse::Success.from(snapshot)].each)

      expect(client.device_details(device(:door_protect))).to have_attributes(device: :door_protect)
      expect(sent).to eq([['StreamHubDeviceService/execute', { hub_id: '0000ABCD', hub_device_id: '0000BEEF' }]])
    end

    it 'reads the details of a hub', :aggregate_failures do
      replying([gw::StreamDeviceInfo::StreamDeviceInfoResponse::Success.from({ snapshot: { device_info: {} } })].each)

      expect(client.hub_details('space-1', '0000ABCD')).not_to be_nil
      expect(sent.last.last).to eq({ device_locator: { space_id: 'space-1', hub: { id: '0000ABCD' } } })
    end

    it 'renames a device and gives the confirmation back', :aggregate_failures do
      success = gw::UpdateHubDevice::UpdateHubDeviceResponse::Success.from({ update_is_pending_hub_in_bsm: {} })
      replying(success)

      expect(client.rename(device(:door_protect), 'Hall')).to eq(success)
      expect(sent.last.last).to eq({ **target, object_type: { door_protect: {} },
                                               update: [{ device_profile_settings: { name: 'Hall' } }] })
    end

    it 'updates the settings of a hub' do
      update = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V2::Hubsvc::Commonmodels::Device::Update.new
      client.update_hub_settings('space-1', '0000ABCD', update)

      expect(sent.last.last).to eq({ device_locator: { space_id: 'space-1', hub: { id: '0000ABCD' } }, update: [{}] })
    end

    it 'reads the scenarios of a space and enables one', :aggregate_failures do
      scenarios = { snapshot: { scenarios: [{ id: 'sc1' }] } }
      replying([gw::StreamLightScenarios::StreamLightScenariosResponse::Success.from(scenarios)].each)

      expect(client.scenarios('space-1').map(&:id)).to eq(%w[sc1])
      client.enable_scenario('space-1', 'sc1')
      expect(sent.last).to eq(['SetScenarioStateService/execute',
                               { space_id: 'space-1', scenario_id: 'sc1', enabled: true }])
    end

    it 'disables a scenario' do
      client.disable_scenario('space-1', 'sc1')

      expect(sent).to eq([['SetScenarioStateService/execute',
                           { space_id: 'space-1', scenario_id: 'sc1', enabled: false }]])
    end

    it 'reads the rooms and the groups of a space', :aggregate_failures do
      snapshot = { snapshot: { rooms: [{ id: 'r1', name: 'Hall' }], security: { groups: [{ id: 'g1' }] } } }
      success = Ajax::Sdk::Cloud::Messages::Api::Mobile::V2::Space::StreamSpaceUpdatesResponse::Success
      replying([success.from(snapshot)].each)

      expect(client.rooms('space-1').map(&:name)).to eq(%w[Hall])
      expect(client.groups('space-1').map(&:id)).to eq(%w[g1])
      expect(sent.map(&:last)).to all(eq({ space_locator: { space_id: 'space-1' } }))
    end

    it 'reads what the signed-in account may do in a space', :aggregate_failures do
      member = { role: :SPACE_MEMBER_ROLE_USER, space_permissions: { permissions: %i[ARM DISARM] },
                 devices_permissions: [{ hub_permissions: { hub_permissions: [:SET_STATE_COMMANDS] } }] }
      success = Ajax::Sdk::Cloud::Messages::Api::Mobile::V2::Space::StreamSpaceUpdatesResponse::Success
      replying([success.from({ snapshot: { current_member: { user_current_member: member } } })].each)
      user = client.current_member('space-1').user_current_member

      expect([user.role, user.space_permissions.permissions]).to eq([:user, %i[arm disarm]])
      expect([user.devices_permissions.first.hub_permissions.hub_permissions, sent.last.last])
        .to eq([%i[set_state_commands], { space_locator: { space_id: 'space-1' } }])
    end

    def catalogue
      player = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V3::Mobilegwsvc::Service::StreamVideoPlayer
      capabilities = { ptz: { flags: [:CAN_PANTILT] }, has_sub_stream: true }
      capable = { video_capabilities: capabilities, audio_settings: { enabled: true } }
      channels = [{ id: 'ch-1', **capable }, { id: 'ch-2', video_capabilities: { ptz: { flags: [:UNSPECIFIED] } } },
                  { id: 'ch-3', video_capabilities: { ptz: { max_presets: 4 } } }]
      edges = [{ id: '0000ABCD', channels: }]
      player::StreamVideoPlayerResponse::Success.from({ initial_state: { video_edges: edges } })
    end

    it 'lists the channels of the space cameras from the player catalogue', :aggregate_failures do
      replying([catalogue].each)
      where = { space_id: 'space-1', video_edge_id: '0000ABCD' }

      expect(client.video_channels('space-1').map { it.to_h.except(:raw) })
        .to eq([{ **where, channel_id: 'ch-1', ptz: true, sub_stream: true, sound: true },
                { **where, channel_id: 'ch-2', ptz: false, sub_stream: false, sound: false },
                { **where, channel_id: 'ch-3', ptz: true, sub_stream: false, sound: false }])
      expect(sent.last).to eq(['StreamVideoPlayerService/execute', { space_id: 'space-1' }])
    end

    def calendar
      start = Time.utc(2026, 10, 1).to_i
      tz_map = [{ day: { seconds: start + 86_400 }, offsets: [0] },
                { day: { seconds: start + (3 * 86_400) }, offsets: [0, -3, -2] }]
      service = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V3::Mobilegwsvc::Service
      service::GetChannelCalendar::GetChannelCalendarResponse::Success
        .from({ calendar: { start_day: { seconds: start }, days: "\x01\x01\x00\x01".b, tz_map: } })
    end

    it 'gives the days with recordings as the app reads its calendar', :aggregate_failures do
      replying(calendar)

      expect(client.archive_days(camera, source: :device)).to eq([Date.new(2026, 10, 1), Date.new(2026, 10, 2),
                                                                  Date.new(2026, 10, 4)])
      expect(sent.last).to eq(['GetChannelCalendarService/execute',
                               { **camera_target, source_type: :SOURCE_TYPE_VIDEO_EDGE_ARCHIVE }])
    end

    it 'lists the cloud fragments of a time range, asked in whole seconds', :aggregate_failures do
      info = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V3::Mobilegwsvc::Service::FindAllCloudArchiveVideoFragmentsInfo
      fragment = { fragment_id: 42, timestamp: { seconds: 150 }, duration: { seconds: 10 } }
      replying(info::FindAllCloudArchiveVideoFragmentsInfoResponse::Success.from({ fragments_info: [fragment] }))

      expect(client.cloud_fragments(camera, during: Time.at(100.5)..Time.at(200.5)))
        .to eq([Ajax::Sdk::Cloud::Fragment.new(id: 42, start: Time.at(150, in: 'UTC'), duration: 10.0)])
      expect(sent.last.last).to eq({ **camera_target, stream_type: :ST_MAIN,
                                                      timestamp_range: { min_value: { seconds: 100, nanos: 0 },
                                                                         max_value: { seconds: 200, nanos: 0 } } })
    end

    it 'asks for an archive export, whose file comes as a notification', :aggregate_failures do
      export = Ajax::Sdk::Cloud::Messages::Api::Mobile::V2::Video::Videoedge::Archive::ExportArchiveResponse::Success
      replying(export.from({ export_id: 'e1' }))

      expect(client.export_archive(camera, [Time.at(100)..Time.at(160)], audio: true)).to eq('e1')
      expect(sent.last.last).to include(
        space_locator: { space_id: 'space-1' }, video_edge_id: '0000ABCD', channel_id: 'ch-1', stream_type: :ST_MAIN,
        with_audio: true, with_figures: false, video_source_type: :VIDEO_SOURCE_TYPE_CLOUD_ARCHIVE
      )
    end

    def quality_answer
      values = { values_temperature: { 3600 => { value_y: 21.5 } },
                 values_humidity: { 3600 => { value_y_range: { min_value_y: 40.0, max_value_y: 45.0 } } } }
      Ajax::Sdk::Cloud::Messages::Mobilegw::Grpc::V1::Homeautomation::Lifequality::LifeQualityDataResponse.from(values)
    end

    it 'reads the life quality history keyed by time', :aggregate_failures do
      replying(quality_answer)
      quality = device(:life_quality, { life_quality_info: {} })
      history = client.life_quality_history(quality, from: Time.at(0), to: Time.at(7200), time_zone: 'Europe/Brussels')
      bucket = Time.at(3600, in: 'UTC')

      expect(history).to have_attributes(temperature: { bucket => 21.5 }, humidity: { bucket => 40.0..45.0 }, co2: {})
      expect(sent.last.last).to eq({ hub_hex_id: '0000ABCD', device_hex_id: '0000BEEF', start_timestamp: 0,
                                     end_timestamp: 7200, discreteness: :LIFE_QUALITY_DATA_DISCRETENESS_HOUR,
                                     time_zone: { id: 'Europe/Brussels', version: '' } })
    end
  end

  context 'when read-only' do
    let(:grpc) { instance_double(GRPC::ClientStub) }

    def answer(path, message)
      klass = Ajax::Sdk::Cloud::Schemas.message(Ajax::Sdk::Cloud::Schemas.rpc(path).response)
      klass.encode(klass.new(message))
    end

    def export_args = [camera, [Time.at(100)..Time.at(160)]]

    def commands
      { turn_on: [device(:relay)], turn_off: [device(:relay)],
        set_brightness: [device(:light_switch_dimmer, gang(1)), 5], open_shutter: [device(:roller_shutter_ls)],
        close_shutter: [device(:roller_shutter_ls)], stop_shutter: [device(:roller_shutter_ls)],
        move_shutter: [device(:roller_shutter_ls), 5], bypass: [device(:door_protect)],
        unbypass: [device(:door_protect)], arm_group: %w[space-1 g1], disarm_group: %w[space-1 g1],
        set_security_mode: ['space-1', :regular], export_archive: export_args,
        panic: ['space-1'], lock: [device(:smart_lock)], unlock: [device(:smart_lock)],
        unlatch: [device(:smart_lock, hub: false)], mute: [fire], mute_fire_detectors: ['0000ABCD'],
        reset_fire_alarm: ['0000ABCD'], rename: [device(:relay), 'x'], update_device_settings: [device(:relay)],
        update_hub_settings: %w[space-1 0000ABCD], enable_scenario: %w[space-1 sc1], disable_scenario: %w[space-1 sc1] }
    end

    def reads
      { rooms: ['space-1'], groups: ['space-1'], current_member: ['space-1'], scenarios: ['space-1'],
        hub_details: %w[space-1 0000ABCD],
        device_details: [device(:door_protect)] }
    end

    before do
      allow(settings).to receive(:read_only).and_return(true)
      allow(GRPC::ClientStub).to receive(:new).and_return(grpc)
      allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
      allow(grpc).to receive(:server_streamer) do |path, *, &relay|
        relay.call(answer(path, { success: { snapshot: {} } }))
      end
      allow(grpc).to receive(:request_response) { |path, *| answer(path, {}) }
    end

    it 'refuses every command' do
      errors = commands.to_h { |name, args| [name, error_of { client.public_send(name, *args) }] }

      expect(errors).to eq(errors.transform_values { Ajax::Sdk::Cloud::ReadOnlyError })
    end

    it 'lets the reading shortcuts through' do
      quality = device(:life_quality, { life_quality_info: {} })
      errors = reads.to_h { |name, args| [name, error_of { client.public_send(name, *args) }] }
      errors[:life_quality_history] = error_of { client.life_quality_history(quality, from: Time.at(0), to: Time.now) }

      expect(errors).to eq(errors.transform_values { nil })
    end
  end
end
