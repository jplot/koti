# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Resources do
  let(:host) { Class.new { include Ajax::Sdk::Cloud::Resources }.new }
  let(:spaces) { '/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination' }
  let(:devices) do
    '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesService/execute'
  end
  let(:log) { '/systems.ajax.api.mobile.v2.notification.NotificationLogService/findNotifications' }

  describe Ajax::Sdk::Cloud::Space do
    it 'maps a raw space entry, trimming the state prefix', :aggregate_failures do
      raw = { id: 's1', hub_id: 'h1', profile: { name: 'Home' },
              security_state: :DISPLAYED_SPACE_SECURITY_STATE_DISARMED,
              hub_connection_status: :CONNECTION_STATUS_ONLINE }

      space = described_class.from(raw)

      expect(space).to have_attributes(id: 's1', hub_id: 'h1', name: 'Home', security_state: :disarmed, online: true)
    end

    it 'gives the values the cloud leaves out at their default' do
      expect(described_class.from({})).to have_attributes(id: '', hub_id: nil, name: '', security_state: :unspecified,
                                                          online: false)
    end
  end

  def success(path, hash)
    Ajax::Sdk::Cloud::Messages.type(Ajax::Sdk::Cloud::Schemas.rpc(path).response)::Success.from(hash)
  end

  it 'lists spaces' do
    allow(host).to receive(:call).and_return(success(spaces, { spaces: [{ id: 's1', profile: { name: 'Home' } }] }))

    expect(host.spaces.map(&:id)).to eq(['s1'])
  end

  it 'arms a space with its locator' do
    allow(host).to receive(:call)

    host.arm('s1')

    expect(host).to have_received(:call).with(%r{/arm\z}, { space_locator: { space_id: 's1' }, ignore_alarms: false })
  end

  it 'reads every page of spaces', :aggregate_failures do
    allow(host).to receive(:call).and_return(
      success(spaces, { spaces: [{ id: 's1' }], pagination: { forward_exclusive_pagination_token: 't2' } }),
      success(spaces, { spaces: [{ id: 's2' }], pagination: { forward_exclusive_pagination_token: '' } })
    )

    expect(host.spaces.map(&:id)).to eq(%w[s1 s2])
    expect(host).to have_received(:call).with(anything, { pagination: { forward_exclusive_pagination_token: 't2' } })
  end

  it 'reads the devices of the first snapshot, leaving out the items that are not devices' do
    items = [{ hub_device: { common_device: { profile: { id: 'd1' } } } }, { smart_lock: { profile: { id: 'd2' } } },
             { access_cards_count: { count: 4 } }]
    snapshot = success(devices, { snapshot: { light_device_items: items } })
    allow(host).to receive(:server_stream).and_return([snapshot].each)

    expect(host.devices('s1').map { [it.id, it.space_id] }).to eq([%w[d1 s1], %w[d2 s1]])
  end

  it 'raises ReadError when the devices stream ends without a message' do
    allow(host).to receive(:server_stream).and_return([].each)

    expect { host.devices('s1') }.to raise_error(Ajax::Sdk::Cloud::ReadError, 'refused')
  end

  def page_of(count, from:, grouped: [])
    notifications = Array.new(count) do |index|
      { id: "n#{from - index}", universal_token: "u#{from - index}", server_timestamp: { seconds: from - index } }
    end
    success(log, { notifications:, offline_notifications_data: [{ notifications: grouped }] })
  end

  it 'reads older notifications from a token' do
    allow(host).to receive(:call).and_return(page_of(0, from: 0))
    host.notifications('s1', older_than: 't1')

    expect(host).to have_received(:call)
      .with(log, { filter: { origin: { space_id: 's1' } }, limit: 20, pagination: { forward_pagination_token: 't1' } })
  end

  it 'reads newer notifications from a token' do
    allow(host).to receive(:call).and_return(page_of(0, from: 0))
    host.notifications('s1', newer_than: 't2')

    expect(host).to have_received(:call).with(log, hash_including(pagination: { backward_pagination_token: 't2' }))
  end

  it 'refuses both directions at once', :aggregate_failures do
    allow(host).to receive(:call)

    expect { host.notifications('s1', older_than: 't1', newer_than: 't2') }.to raise_error(ArgumentError, /both/)
    expect(host).not_to have_received(:call)
  end

  it 'walks the history page by page until a short page', :aggregate_failures do
    allow(host).to receive(:call).and_return(page_of(20, from: 1000), page_of(20, from: 980), page_of(3, from: 960))

    expect(host.notification_history('s1').to_a.map(&:id)).to eq((958..1000).to_a.reverse.map { "n#{it}" })
    expect(host).to have_received(:call).exactly(3).times
    expect(host).to have_received(:call).with(log, hash_including(pagination: { forward_pagination_token: 'u981' }))
  end

  def entry(seconds) = { id: "n#{seconds}", universal_token: "u#{seconds}", server_timestamp: { seconds: } }

  it 'pages from the oldest notification outside an offline group, most recent first', :aggregate_failures do
    group = { parent_notification_id: 'n103', notifications: [{ **entry(50), id: 'c50' }] }
    first = success(log, { notifications: [entry(101), entry(103), entry(102)], offline_notifications_data: [group] })
    allow(host).to receive(:call).and_return(first, page_of(0, from: 0))

    history = host.notification_history('s1', limit: 3).to_a
    expect(history.map { [it.id, it.parent_id] }).to eq([['n103', nil], ['n102', nil], ['n101', nil], %w[c50 n103]])
    expect(host).to have_received(:call).with(log, hash_including(pagination: { forward_pagination_token: 'u101' }))
  end

  it 'stops the history on an empty page', :aggregate_failures do
    allow(host).to receive(:call).and_return(page_of(0, from: 0))

    expect(host.notification_history('s1', limit: 0).to_a).to be_empty
    expect(host).to have_received(:call).once
  end

  it 'ends the history on a page short of notifications outside an offline group' do
    grouped = Array.new(5) { |index| { id: "c#{index}", server_timestamp: { seconds: 900 - index } } }
    allow(host).to receive(:call).and_return(page_of(19, from: 1000, grouped:))

    expect(host.notification_history('s1').to_a.size).to eq(24)
  end

  it 'adds the notifications grouped under an offline one, most recent first' do
    child = { id: 'child', server_timestamp: { seconds: 150 } }
    allow(host).to receive(:call).and_return(page_of(1, from: 100, grouped: [child]))

    expect(host.notifications('s1').map(&:id)).to eq(%w[child n100])
  end

  it 'reads notifications of a space' do
    path = '/systems.ajax.api.mobile.v2.notification.NotificationLogService/findNotifications'
    allow(host).to receive(:call).and_return(success(path, { notifications: [{ id: 'n1' }] }))

    expect(host.notifications('s1', limit: 5).map(&:id)).to eq(['n1'])
  end
end
