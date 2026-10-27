# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Device do
  def hub_device(statuses: [], **profile)
    { hub_device: { common_device: { profile: { id: '0A1B2C3D', name: 'Front door', statuses:, **profile },
                                     hub_id: '00FF00FF', object_type: { door_protect_plus: {} } } } }
  end

  it 'maps the profile of a hub device' do
    device = described_class.from(hub_device(room_id: '00000001', states: [:LIGHT_DEVICE_STATE_OFFLINE],
                                             malfunctions: 2, bypassed: true))

    expect(device).to have_attributes(id: '0A1B2C3D', name: 'Front door', kind: :door_protect_plus,
                                      hub_id: '00FF00FF', room_id: '00000001', group_id: nil,
                                      states: [:offline], malfunctions: 2, bypassed: true)
  end

  it 'gives the values the cloud leaves out at their default' do
    expect(described_class.from(hub_device)).to have_attributes(
      states: [], malfunctions: 0, bypassed: false, battery: nil, signal: nil, temperature: nil, flags: []
    )
  end

  it 'reads an exact battery charge' do
    device = described_class.from(hub_device(statuses: [{ battery: { battery_state: :BATTERY_STATE_WARNING,
                                                                     charge_level_percentage: 18 } }]))

    expect(device.battery).to eq(Ajax::Sdk::Cloud::Battery.new(state: :warning, charge: 18, exact: true))
  end

  it 'marks the charge of a device that reports no percentage as inexact' do
    device = described_class.from(hub_device(statuses: [{ battery: { battery_state: :BATTERY_STATE_OK,
                                                                     charge_level_percentage: 100,
                                                                     is_without_charge: true } }]))

    expect(device.battery).to eq(Ajax::Sdk::Cloud::Battery.new(state: :ok, charge: 100, exact: false))
  end

  it 'reads a battery status whose fields are all at their default' do
    device = described_class.from(hub_device(statuses: [{ battery: {} }]))

    expect(device.battery).to eq(Ajax::Sdk::Cloud::Battery.new(state: :unspecified, charge: 0, exact: true))
  end

  it 'reads the signal level and the temperature' do
    signal = { signal_strength: { device_signal_level: :DEVICE_SIGNAL_LEVEL_WEAK } }
    device = described_class.from(hub_device(statuses: [signal, { temperature: { value: 22 } }]))

    expect(device).to have_attributes(signal: :weak, temperature: 22)
  end

  it 'lists the statuses that carry no value as flags, never a valued one left empty' do
    device = described_class.from(hub_device(statuses: [{ door_opened: {} }, { nfc: {} }, { armed_in_night_mode: {} }]))

    expect(device.flags).to eq(%i[door_opened armed_in_night_mode])
  end

  it 'names a device outside the hub after its item' do
    device = described_class.from({ smart_lock: { profile: { id: '1', name: 'Lock' } } })

    expect(device).to have_attributes(id: '1', kind: :smart_lock, hub_id: nil)
  end

  it 'is nil for an item that is not a device' do
    expect(described_class.from({ access_cards_count: { count: 4 } })).to be_nil
  end
end
