# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Notification do
  let(:raw) do
    { id: 'n1', server_timestamp: { seconds: 1_700_000_000, nanos: 250_000_000 }, folder: :FOLDER_ALARM,
      importance: :IMPORTANCE_WARNING, read_by_user: true,
      content: { hub_notification_content: {
        qualifier: { tag: { motion_detected: {} }, transition: { impulse: {} } },
        source: { type: :MOTION_PROTECT_CURTAIN, id: '0A1B2C3D', name: 'Hall' }
      } } }
  end

  it 'maps a hub notification' do
    expect(described_class.from(raw)).to have_attributes(
      id: 'n1', kind: :hub, event: :motion_detected, transition: :impulse, folder: :alarm, importance: :warning,
      read: true, source: Ajax::Sdk::Cloud::Source.new(type: :motion_protect_curtain, id: '0A1B2C3D', name: 'Hall')
    )
  end

  it 'reads the server time in UTC' do
    expect(described_class.from(raw).time).to eq(Time.at(1_700_000_000, 250, :millisecond)).and be_utc
  end

  it 'reads the source of a space notification raised by the hub' do
    qualifier = { tag: { space_disarmed: {} }, transition: { triggered: {} } }
    content = { space_notification_content: { qualifier:, hub_source: { type: :USER, id: '5A5A5A5A' } } }

    expect(described_class.from({ id: 'n2', content: })).to have_attributes(
      kind: :space, event: :space_disarmed, source: Ajax::Sdk::Cloud::Source.new(type: :user, id: '5A5A5A5A', name: nil)
    )
  end

  it 'gives the values the cloud leaves out at their default' do
    expect(described_class.from({ id: 'n3' })).to have_attributes(
      time: nil, kind: :unknown, event: nil, transition: nil, source: nil, folder: :unspecified,
      importance: :unspecified, read: false, token: ''
    )
  end

  it 'keeps the universal token' do
    expect(described_class.from({ **raw, universal_token: 'u1' }).token).to eq('u1')
  end
end
