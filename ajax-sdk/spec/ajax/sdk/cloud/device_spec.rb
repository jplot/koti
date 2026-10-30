# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Device do
  def hub_device(statuses: [], spread: [], **profile)
    { hub_device: { common_device: { profile: { id: '0A1B2C3D', name: 'Front door', statuses:, **profile },
                                     hub_id: '00FF00FF', object_type: { door_protect_plus: {} } },
                    spread_properties: spread } }
  end

  def from(item)
    light = Ajax::Sdk::Cloud::Messages::Api::Ecosystem::V3::Mobilegwsvc::Commonmodels::Space::Device::Light
    described_class.from(light::LightDeviceItem.from(item), space_id: 'space-1')
  end

  def channel(number, on, name = nil, brightness = nil)
    Ajax::Sdk::Cloud::Channel.new(number:, on:, name:, brightness:)
  end

  def channel_id(number) = :"CHANNEL_ID_#{number}"

  it 'maps the profile of a hub device' do
    device = from(hub_device(room_id: '00000001', states: [:LIGHT_DEVICE_STATE_OFFLINE],
                             malfunctions: 2, bypassed: true))

    expect(device).to have_attributes(id: '0A1B2C3D', name: 'Front door', kind: :door_protect_plus,
                                      hub_id: '00FF00FF', space_id: 'space-1', room_id: '00000001', group_id: nil,
                                      states: [:offline], malfunctions: 2, bypassed: true)
  end

  it 'gives the values the cloud leaves out at their default' do
    expect(from(hub_device)).to have_attributes(
      states: [], malfunctions: 0, bypassed: false, battery: nil, signal: nil, temperature: nil, flags: [],
      channels: [], shutter: nil, lock: nil, life_quality: nil, mute_command: nil
    )
  end

  it 'reads an exact battery charge' do
    device = from(hub_device(statuses: [{ battery: { battery_state: :BATTERY_STATE_WARNING,
                                                     charge_level_percentage: 18 } }]))

    expect(device.battery).to eq(Ajax::Sdk::Cloud::Battery.new(state: :warning, charge: 18, exact: true))
  end

  it 'marks the charge of a device that reports no percentage as inexact' do
    device = from(hub_device(statuses: [{ battery: { battery_state: :BATTERY_STATE_OK,
                                                     charge_level_percentage: 100,
                                                     is_without_charge: true } }]))

    expect(device.battery).to eq(Ajax::Sdk::Cloud::Battery.new(state: :ok, charge: 100, exact: false))
  end

  it 'reads a battery status whose fields are all at their default' do
    device = from(hub_device(statuses: [{ battery: {} }]))

    expect(device.battery).to eq(Ajax::Sdk::Cloud::Battery.new(state: :unspecified, charge: 0, exact: true))
  end

  it 'reads the signal level and the temperature' do
    signal = { signal_strength: { device_signal_level: :DEVICE_SIGNAL_LEVEL_WEAK } }
    device = from(hub_device(statuses: [signal, { temperature: { value: 22 } }]))

    expect(device).to have_attributes(signal: :weak, temperature: 22)
  end

  it 'lists the statuses that carry no value as flags, never a valued one left empty' do
    device = from(hub_device(statuses: [{ door_opened: {} }, { nfc: {} }, { armed_in_night_mode: {} }]))

    expect(device.flags).to eq(%i[door_opened armed_in_night_mode])
  end

  it 'reads the channels of a two-gang light switch' do
    gangs = [{ light_switch_channel: { id: channel_id(1), name: 'Hall', state: :STATE_ON } },
             { light_switch_channel: { id: channel_id(2), name: 'Stairs', state: :STATE_OFF } }]

    expect(from(hub_device(spread: gangs)).channels).to eq([channel(1, true, 'Hall'), channel(2, false, 'Stairs')])
  end

  it 'reads the channels of a multi-channel relay' do
    relays = [{ channel: { channel_id: 1, is_channel_on: true, channel_name: 'Pump' } }, { channel: { channel_id: 2 } }]

    expect(from(hub_device(spread: relays)).channels).to eq([channel(1, true, 'Pump'), channel(2, false)])
  end

  it 'reads a dimmer brightness' do
    dimmer = { light_switch_channel: { id: channel_id(1), state: :STATE_ON, brightness: { level: 40 } } }

    expect(from(hub_device(spread: [dimmer])).channels).to eq([channel(1, true, '', 40)])
  end

  it 'reads a socket, and a valve whose state is unknown' do
    outlets = [{ socket_base_channel: { id: channel_id(1), state: :STATE_ON } },
               { water_stop_channel: { id: channel_id(1), state: :STATE_UNKNOWN } }]

    expect(from(hub_device(spread: outlets)).channels).to eq([channel(1, true), channel(1, nil)])
  end

  it 'reads a shutter opening and its movement', :aggregate_failures do
    shutter = ->(position) { from(hub_device(spread: [{ roller_position: position }])).shutter }

    expect(shutter.call({ idle: { fully_opened: {} } })).to have_attributes(position: 100, moving: nil)
    expect(shutter.call({ idle: { fully_closed: {} } }).position).to eq(0)
    expect(shutter.call({ idle: { partial_percent: { percent: 30 } } }).position).to eq(30)
    expect(shutter.call({ moving: { direction: :DIRECTION_CLOSING } }))
      .to eq(Ajax::Sdk::Cloud::Shutter.new(position: nil, moving: :closing))
  end

  it 'reads the state of a smart lock' do
    jeweller = hub_device(spread: [{ smart_lock_control: { state: :LOCK_STATE_LOCKED } }])
    cloud = { smart_lock: { profile: { id: '1' },
                            spread_properties: [{ smart_lock_control: { state: :LOCK_STATE_UNLOCKED } }] } }

    expect([from(jeweller).lock, from(cloud).lock]).to eq(%i[locked unlocked])
  end

  it 'reads LifeQuality measures' do
    info = { life_quality_info: { actual_temperature: 21.5, actual_humidity: 40.0, actual_co2: 600 } }

    expect(from(hub_device(spread: [info])).life_quality)
      .to eq(Ajax::Sdk::Cloud::LifeQuality.new(temperature: 21.5, humidity: 40.0, co2: 600))
  end

  it 'reads the mute command of a fire detector' do
    button = { fire_device_action_button: { mute_button: { mute_command: :MUTE_COMMAND_OWN_PLUS_EXTERNAL } } }

    expect(from(hub_device(spread: [button])).mute_command).to eq(:own_plus_external)
  end

  it 'names a device outside the hub after its item' do
    device = from({ smart_lock: { profile: { id: '1', name: 'Lock' } } })

    expect(device).to have_attributes(id: '1', kind: :smart_lock, hub_id: nil)
  end

  it 'is nil for an item that is not a device' do
    expect(from({ access_cards_count: { count: 4 } })).to be_nil
  end
end
