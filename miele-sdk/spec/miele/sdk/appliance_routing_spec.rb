# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { described_class.new('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:leaf) { "#{['000e0002063200000000000100010407'].pack('H*')}  " }
  let(:fake) do
    FakeAppliance.start do |request|
      case request.path
      when '/Devices/' then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      when %r{/DOP2/} then [404, {}, '']
      else [200, {}, '{"Status":5}']
      end
    end
  end
  let(:cloud) do
    FakeCloud.start do |request|
      case request.path
      when %r{\A/V2/Devices/\d+/DOP2/} then [200, {}, leaf]
      when %r{\A/V2/Devices/\d+/DOP/} then FakeCloud.json('Response' => '8E0111000000')
      when %r{\A/V2/Devices/\d+/Ident\z} then FakeCloud.json('DeviceType' => 13, 'ProtocolVersion' => 4)
      when '/V2/Devices' then FakeCloud.json([{ host: 'Miele-0000000000000000.local.', devices: [{ mac: fab }] }])
      when '/V2/GroupKeyId/'
        FakeCloud.json([{ groupId: FakeAppliance::GROUP_ID, groupKey: FakeAppliance::GROUP_KEY }])
      end
    end
  end

  before do
    connect_to(fake)
    Miele::Sdk.configure do |config|
      config.country = 'FR'
      config.email = 'koti@example.com'
      config.password = 'secret'
      config.locales_host = cloud.url
    end
  end

  after do
    fake.stop
    cloud.stop
  end

  def through_cloud = cloud.requests.map(&:path).grep(%r{\A/V2/Devices/\d})

  def by_cloud = described_class.new('127.0.0.1', fab:, cloud: Miele::Sdk.cloud)

  it 'raises a local 404, though an account is set', :aggregate_failures do
    expect { appliance.dop2(2, 1586) }.to raise_error(Miele::Sdk::NotFoundError)
    expect(through_cloud).to be_empty
  end

  it 'reads DOP2 through the cloud it is given, never locally', :aggregate_failures do
    expect(by_cloud.dop2(2, 1586).fields).to eq(1 => Miele::Sdk::Dop2::Field[:e8, 7])
    expect(through_cloud).to eq(["/V2/Devices/#{fab}/DOP2/2/1586"])
    expect(fake.requests).to be_empty
  end

  it 'needs the fab of an appliance reached through the cloud, which names appliances by it' do
    expect { described_class.new('127.0.0.1', cloud: Miele::Sdk.cloud) }.to raise_error(ArgumentError, /fab/)
  end

  it 'builds the family class through the cloud it is given, sending nothing locally', :aggregate_failures do
    expect(described_class.for('127.0.0.1', fab:, cloud: Miele::Sdk.cloud)).to be_a(Miele::Sdk::Oven)
    expect(fake.requests).to be_empty
  end

  it 'reads the module of an appliance reached through the cloud locally, the cloud having no such resource',
     :aggregate_failures do
    by_cloud.info
    expect(fake.requests.map(&:path)).to eq(['/Info'])
    expect(cloud.requests.map(&:path)).not_to include('/V2/Info')
  end

  it 'sends Dop1 through the very cloud it is given, naming the module that cloud lists' do
    channel = instance_double(Miele::Sdk::Cloud::Channel,
                              devices: [Miele::Sdk::Cloud::Channel::Device.new(fab:, host: 'module.local',
                                                                               ident: nil, state: nil)])
    allow(channel).to receive(:request).and_return(Miele::Sdk::Connection::Response.new(200, '{}'))
    described_class.new('127.0.0.1', fab:, cloud: channel).dop1('8E0101000000')
    expect(channel).to have_received(:request)
      .with(:post, "/Devices/#{fab}/DOP/", body: anything, kind: :json, host: 'module.local')
  end

  it 'names the module host when Dop1 goes through the cloud' do
    by_cloud.dop1('8E0101000000')
    expect(cloud.requests.find { it.path.end_with?('/DOP/') }.headers['host']).to eq('Miele-0000000000000000.local')
  end

  it 'reads State locally when the appliance serves it', :aggregate_failures do
    expect(appliance.state.status).to eq(:running)
    expect(cloud.requests).to be_empty
  end

  it 'lists appliances from the account' do
    expect(Miele::Sdk.appliances)
      .to contain_exactly(have_attributes(fab:, host: 'Miele-0000000000000000.local.'))
  end

  it 'reaches the account appliances locally unless asked otherwise' do
    expect([Miele::Sdk.appliances, Miele::Sdk.appliances(through_cloud: true)].map { it.map(&:through_cloud?) })
      .to eq([[false], [true]])
  end

  it 'reaches the account appliances through its cloud when asked', :aggregate_failures do
    Miele::Sdk.appliances(through_cloud: true).first.dop2(2, 1586)
    expect(through_cloud).to eq(["/V2/Devices/#{fab}/DOP2/2/1586"])
    expect(fake.requests).to be_empty
  end

  it 'signs locally with the household key read from the cloud', :aggregate_failures do
    Miele::Sdk.configure do |config|
      config.group_id = nil
      config.group_key = nil
    end
    expect(appliance.state.status).to eq(:running)
    expect(fake.requests.last.verified).to be(true)
  end
end
