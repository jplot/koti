# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Resources do
  let(:host) { Class.new { include Ajax::Sdk::Cloud::Resources }.new }
  let(:spaces) { '/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination' }
  let(:devices) do
    '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesService/execute'
  end

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

    expect(host.devices('s1').map(&:id)).to eq(%w[d1 d2])
  end

  it 'raises ReadError when the devices stream ends without a message' do
    allow(host).to receive(:server_stream).and_return([].each)

    expect { host.devices('s1') }.to raise_error(Ajax::Sdk::Cloud::ReadError, 'refused')
  end

  it 'reads notifications of a space' do
    path = '/systems.ajax.api.mobile.v2.notification.NotificationLogService/findNotifications'
    allow(host).to receive(:call).and_return(success(path, { notifications: [{ id: 'n1' }] }))

    expect(host.notifications('s1', limit: 5).map(&:id)).to eq(['n1'])
  end
end
