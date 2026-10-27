# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Resources do
  let(:host) do
    Class.new do
      include Ajax::Sdk::Cloud::Resources

      def read_only? = false
    end.new
  end

  describe Ajax::Sdk::Cloud::Space do
    it 'maps a raw space entry, trimming the state prefix', :aggregate_failures do
      raw = { id: 's1', hub_id: 'h1', profile: { name: 'Home' },
              security_state: :DISPLAYED_SPACE_SECURITY_STATE_DISARMED,
              hub_connection_status: :CONNECTION_STATUS_ONLINE }

      space = described_class.from(raw)

      expect(space).to have_attributes(id: 's1', hub_id: 'h1', name: 'Home', security_state: :disarmed, online: true)
    end
  end

  it 'lists spaces' do
    allow(host).to receive(:call).and_return({ success: { spaces: [{ id: 's1', profile: { name: 'Home' } }] } })

    expect(host.spaces.map(&:id)).to eq(['s1'])
  end

  it 'arms a space with its locator' do
    allow(host).to receive(:call).and_return({ success: {} })

    host.arm('s1')

    expect(host).to have_received(:call).with(%r{/arm\z}, { space_locator: { space_id: 's1' }, ignore_alarms: false })
  end

  it 'raises CommandError with the failure reason' do
    allow(host).to receive(:call).and_return({ failure: { hub_offline: {} } })

    expect { host.disarm('s1') }.to raise_error(Ajax::Sdk::Cloud::CommandError, /hub_offline/)
  end

  it 'reads every page of spaces', :aggregate_failures do
    allow(host).to receive(:call).and_return(
      { success: { spaces: [{ id: 's1' }], pagination: { forward_exclusive_pagination_token: 't2' } } },
      { success: { spaces: [{ id: 's2' }], pagination: { forward_exclusive_pagination_token: '' } } }
    )

    expect(host.spaces.map(&:id)).to eq(%w[s1 s2])
    expect(host).to have_received(:call).with(anything, { pagination: { forward_exclusive_pagination_token: 't2' } })
  end

  it 'raises ReadError when the gateway refuses a read' do
    allow(host).to receive(:call).and_return({ failure: { bad_request: {} } })

    expect { host.spaces }.to raise_error(Ajax::Sdk::Cloud::ReadError, /bad_request/)
  end

  it 'reads the devices of the first snapshot, leaving out the items that are not devices' do
    items = [{ hub_device: { common_device: { profile: { id: 'd1' } } } }, { smart_lock: { profile: { id: 'd2' } } },
             { access_cards_count: { count: 4 } }]
    allow(host).to receive(:server_stream).and_return([{ success: { snapshot: { light_device_items: items } } }].each)

    expect(host.devices('s1').map(&:id)).to eq(%w[d1 d2])
  end

  it 'raises ReadError when the devices stream answers a failure' do
    allow(host).to receive(:server_stream).and_return([{ failure: { space_not_found: {} } }].each)

    expect { host.devices('s1') }.to raise_error(Ajax::Sdk::Cloud::ReadError, /space_not_found/)
  end

  it 'reads notifications of a space' do
    allow(host).to receive(:call).and_return({ success: { notifications: [{ id: 'n1' }] } })

    expect(host.notifications('s1', limit: 5)).to eq([{ id: 'n1' }])
  end
end
