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

  it 'reads the first devices snapshot' do
    snapshot = { success: { snapshot: { light_device_items: [{ hub_device: {} }, { smart_lock: {} }] } } }
    allow(host).to receive(:server_stream).and_return([snapshot].each)

    expect(host.devices('s1').size).to eq(2)
  end

  it 'reads notifications of a space' do
    allow(host).to receive(:call).and_return({ success: { notifications: [{ id: 'n1' }] } })

    expect(host.notifications('s1', limit: 5)).to eq([{ id: 'n1' }])
  end
end
