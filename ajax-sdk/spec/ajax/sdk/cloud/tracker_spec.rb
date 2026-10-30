# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Tracker do
  subject(:tracker) { described_class.new('space-1') }

  def success(name, hash) = Ajax::Sdk::Cloud::Messages.type(name)::Success.from(hash)

  def devices(hash)
    success('systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesResponse', hash)
  end

  def space(hash) = success('systems.ajax.api.mobile.v2.space.StreamSpaceUpdatesResponse', hash)

  def summary(hash) = success('systems.ajax.api.mobile.v2.space.user.StreamUserSpacesResponse', hash)

  def log(*events) = success('systems.ajax.api.mobile.v2.notification.StreamNotificationLogResponse', { events: })

  def door(charge: 100, statuses: [{ battery: { charge_level_percentage: charge } }], states: [])
    { hub_device: { common_device: { hub_id: '0000ABCD', object_type: { door_protect: {} },
                                     profile: { id: '0000BEEF', name: 'Door', statuses:, states: } } } }
  end

  def key = [:hub_device, '0000ABCD', '0000BEEF']

  def snapshot(*items) = devices({ snapshot: { light_device_items: items } })

  def update(change, device_id: { hub_light_device_id: { hub_id: '0000ABCD', device_id: '0000BEEF' } })
    devices({ updates: { updates: [{ device_id:, **change }] } })
  end

  def created(seconds)
    { notification_created: { id: "n#{seconds}", universal_token: "u#{seconds}", server_timestamp: { seconds: } } }
  end

  def lock_update(type)
    property = { smart_lock_control: { state: :LOCK_STATE_LOCKED } }
    update({ light_smart_lock_update: { spread_properties_update: { update_type: type, spread_property: property } } },
           device_id: { smart_lock_id: { id: 'lock-1' } })
  end

  def offline(type) = { state_update: { state: :LIGHT_DEVICE_STATE_OFFLINE, update_type: type } }

  def space_update(type, **entity) = space({ update: { space_update_type: type, **entity } })

  it 'adds every device of a first snapshot', :aggregate_failures do
    events = tracker.apply(:devices, snapshot(door, { access_cards_count: { count: 2 } }))

    expect(events.map { [it.kind, it.key, it.before] }).to eq([[:device, key, nil]])
    expect(events.first.after).to have_attributes(id: '0000BEEF', space_id: 'space-1')
    expect(events.first.state.devices.keys).to eq([key])
  end

  it 'emits the changes a later snapshot reveals' do
    tracker.apply(:devices, snapshot(door(charge: 100)))
    events = tracker.apply(:devices, snapshot(door(charge: 50)))

    expect(events.map { [it.before.battery.charge, it.after.battery.charge] }).to eq([[100, 50]])
  end

  it 'removes a device on REMOVE', :aggregate_failures do
    tracker.apply(:devices, snapshot(door))
    events = tracker.apply(:devices, update({ snapshot_update: { update_type: :UPDATE_TYPE_REMOVE } }))

    expect(events.map { [it.key, it.after] }).to eq([[key, nil]])
    expect(tracker.state.devices).to be_empty
  end

  it 'replaces a status of the same kind and keeps the others' do
    signal = { signal_strength: { device_signal_level: :DEVICE_SIGNAL_LEVEL_WEAK } }
    tracker.apply(:devices, snapshot(door(statuses: [{ battery: { charge_level_percentage: 90 } }, signal])))
    battery = { status: { battery: { charge_level_percentage: 40 } }, update_type: :UPDATE_TYPE_UPDATE }

    expect(tracker.apply(:devices, update({ status_update: battery })).first.after)
      .to have_attributes(battery: have_attributes(charge: 40), signal: :weak)
  end

  it 'keeps one wire input status per contact' do
    tracker.apply(:devices, snapshot(door(statuses: [{ wire_input_status: { contact_index: 1 } }])))
    second = { status: { wire_input_status: { contact_index: 2, is_alert: true } }, update_type: :UPDATE_TYPE_ADD }
    tracker.apply(:devices, update({ status_update: second }))

    expect(tracker.state.devices.fetch(key).raw.dig(:hub_device, :common_device, :profile, :statuses).size).to eq(2)
  end

  it 'adds and removes a device state' do
    tracker.apply(:devices, snapshot(door))
    states = %i[UPDATE_TYPE_ADD UPDATE_TYPE_REMOVE].map do |type|
      tracker.apply(:devices, update({ state_update: { state: :LIGHT_DEVICE_STATE_OFFLINE, update_type: type } }))
             .first.after.states
    end

    expect(states).to eq([[:offline], []])
  end

  it 'replaces the malfunctions count' do
    tracker.apply(:devices, snapshot(door))

    expect(tracker.apply(:devices, update({ malfunctions_update: 3 })).first.after.malfunctions).to eq(3)
  end

  it 'replaces or empties the properties of a cloud lock', :aggregate_failures do
    tracker.apply(:devices, snapshot({ smart_lock: { profile: { id: 'lock-1' } } }))

    expect(tracker.apply(:devices, lock_update(:UPDATE_TYPE_UPDATE)).first.after.lock).to eq(:locked)
    expect(tracker.apply(:devices, lock_update(:UPDATE_TYPE_REMOVE)).first.after.lock).to be_nil
  end

  it 'overwrites a field of a video edge' do
    tracker.apply(:devices, snapshot({ video_edge: { profile: { id: 'nvr-1', name: 'NVR' } } }))
    edge = { video_edge_id: { id: 'nvr-1' } }
    events = tracker.apply(:devices, update({ light_video_edge_update: { name: 'Garage' } }, device_id: edge))

    expect(events.map { [it.key, it.before.name, it.after.name] }).to eq([[[:video_edge, 'nvr-1'], 'NVR', 'Garage']])
  end

  def edge_update(type, online)
    property = { update_type: type, spread_properties: { channels: { online_count: online } } }
    update({ light_video_edge_update: { spread_properties_update: property } },
           device_id: { video_edge_id: { id: 'nvr-1' } })
  end

  it 'replaces or removes a property of a video edge by its kind', :aggregate_failures do
    edge = { profile: { id: 'nvr-1' }, spread_properties: [{ channels: {} }] }
    tracker.apply(:devices, snapshot({ video_edge: edge }))
    replaced = tracker.apply(:devices, edge_update(:UPDATE_TYPE_UPDATE, 3)).first.after
    removed = tracker.apply(:devices, edge_update(:UPDATE_TYPE_REMOVE, 3)).first.after

    expect(replaced.raw.dig(:video_edge, :spread_properties)).to eq([{ channels: { online_count: 3 } }])
    expect(removed.raw.dig(:video_edge, :spread_properties)).to eq([])
  end

  it 'keys a video channel by its edge and overwrites one of its fields' do
    channel = { profile: { id: 'ch1' }, video_edge_channel_properties: { video_edge_id: 'nvr-1' } }
    tracker.apply(:devices, snapshot({ video_edge_channel: channel }))
    backup = { light_video_edge_channel_update: { backup_channel_properties: { hub_id: '0000ABCD' } } }
    reference = { video_edge_channel_reference: { video_edge_id: 'nvr-1', channel_id: 'ch1' } }

    event = tracker.apply(:devices, update(backup, device_id: reference)).first

    properties = event.after.raw.dig(:video_edge_channel, :video_edge_channel_properties)
    expect([event.key, properties[:backup_channel_properties]])
      .to eq([[:video_edge_channel, 'nvr-1', 'ch1'], { hub_id: '0000ABCD' }])
  end

  it 'emits nothing for a snapshot that repeats what updates gave' do
    signal = { signal_strength: { device_signal_level: :DEVICE_SIGNAL_LEVEL_WEAK } }
    tracker.apply(:devices, snapshot(door(statuses: [{ battery: { charge_level_percentage: 90 } }, signal])))
    battery = { status: { battery: { charge_level_percentage: 40 } }, update_type: :UPDATE_TYPE_UPDATE }
    [{ status_update: battery }, { malfunctions_update: 0 }, offline(:UPDATE_TYPE_ADD), offline(:UPDATE_TYPE_REMOVE)]
      .each { tracker.apply(:devices, update(it)) }

    repeated = snapshot(door(statuses: [{ battery: { charge_level_percentage: 40 } }, signal]))
    expect(tracker.apply(:devices, repeated)).to be_empty
  end

  it 'emits nothing for an initial state that repeats a lite space update' do
    tracker.apply(:summary, summary({ initial_state: { spaces: [{ id: 'space-1', malfunctions_count: 2 }] } }))
    cleared = { space_id: 'space-1', lite_space_updated: { id: 'space-1', malfunctions_count: 0 } }
    tracker.apply(:summary, summary({ lite_space_event: cleared }))

    expect(tracker.apply(:summary, summary({ initial_state: { spaces: [{ id: 'space-1' }] } }))).to be_empty
  end

  it 'skips a device update it cannot key' do
    tracker.apply(:devices, snapshot(door))

    expect(tracker.apply(:devices, update({ malfunctions_update: 3 }, device_id: nil))).to be_empty
  end

  it 'replaces the security mode and ignores its REMOVE', :aggregate_failures do
    mode = { security_mode: { displayed_security_state: :DISPLAYED_SPACE_SECURITY_STATE_ARMED } }
    added = tracker.apply(:space, space({ update: { space_update_type: :SPACE_UPDATE_TYPE_ADD, **mode } }))
    removed = tracker.apply(:space, space({ update: { space_update_type: :SPACE_UPDATE_TYPE_REMOVE, **mode } }))

    expect(added.map { [it.kind, it.after.displayed_security_state] }).to eq([%i[security armed]])
    expect([removed, tracker.state.security.displayed_security_state]).to eq([[], :armed])
  end

  it 'upserts and removes groups and rooms', :aggregate_failures do
    tracker.apply(:space, space({ snapshot: { rooms: [{ id: 'r1' }], security: { groups: [{ id: 'g1' }] } } }))
    upsert = tracker.apply(:space, space_update(:SPACE_UPDATE_TYPE_UPDATE, group: { id: 'g2' }))
    remove = tracker.apply(:space, space_update(:SPACE_UPDATE_TYPE_REMOVE, room: { id: 'r1' }))

    expect((upsert + remove).map { [it.kind, it.key, it.before.nil?, it.after.nil?] })
      .to eq([[:group, 'g2', true, false], [:room, 'r1', false, true]])
    expect([tracker.state.groups.keys, tracker.state.rooms.keys]).to eq([%w[g1 g2], []])
  end

  it 'copies the one field of a lite space update', :aggregate_failures do
    home = { id: 'space-1', profile: { name: 'Home' }, hub_connection_status: :CONNECTION_STATUS_ONLINE }
    tracker.apply(:summary, summary({ initial_state: { spaces: [home, { id: 'other' }] } }))
    offline = { id: 'space-1', hub_connection_status: :CONNECTION_STATUS_OFFLINE }
    event = { space_id: 'space-1', lite_space_updated: offline }
    events = tracker.apply(:summary, summary({ lite_space_event: event }))

    expect(events.map { [it.kind, it.before.online, it.after.online, it.after.name] })
      .to eq([[:space, true, false, 'Home']])
  end

  it 'forgets a removed space and ignores the others', :aggregate_failures do
    tracker.apply(:summary, summary({ initial_state: { spaces: [{ id: 'space-1' }] } }))
    created = { lite_space_created: { lite_space: { id: 'other' } } }
    other = tracker.apply(:summary, summary({ lite_space_event: created }))
    removed = tracker.apply(:summary, summary({ lite_space_event: { lite_space_removed: { id: 'space-1' } } }))

    expect([other, removed.map { [it.kind, it.after] }, tracker.state.space]).to eq([[], [[:space, nil]], nil])
  end

  it 'emits a notification, then its update with what it was' do
    tracker.apply(:notifications, log(created(10)))
    read = { notification_updated: { **created(10)[:notification_created], read_by_user: true } }
    events = tracker.apply(:notifications, log(read))

    expect(events.map { [it.kind, it.key, it.before.read, it.after.read] }).to eq([[:notification, 'n10', false, true]])
  end

  it 'keeps the 500 newest notifications', :aggregate_failures do
    tracker.apply(:notifications, log(*(1..501).map { created(it) }))

    expect(tracker.apply(:notifications, log(created(1))).first.before).to be_nil
    read = { notification_updated: { **created(2)[:notification_created], read_by_user: true } }
    expect(tracker.apply(:notifications, log(read)).first.before).not_to be_nil
  end
end
