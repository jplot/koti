# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { Miele::Sdk.appliance('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:leaf) { "#{['000e0002063200000000000100010407'].pack('H*')}  " }
  let(:fake) do
    FakeAppliance.start do |request|
      case request.path
      when '/Devices/' then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      when %r{/DOP2?/} then [404, {}, '']
      else [200, {}, '{"Status":5}']
      end
    end
  end
  let(:cloud) do
    FakeCloud.start do |request|
      case request.path
      when %r{\A/V2/Devices/\d+/DOP2/} then [200, {}, leaf]
      when %r{\A/V2/Devices/\d+/DOP/} then FakeCloud.json('Response' => '8E0111000000')
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

  it 'reads DOP2 through the cloud when the appliance answers 404 locally', :aggregate_failures do
    expect(appliance.dop2(2, 1586).fields).to eq(1 => Miele::Sdk::Dop2::Field[:e8, 7])
    expect(through_cloud).to eq(["/V2/Devices/#{fab}/DOP2/2/1586"])
  end

  it 'sends the next DOP2 request straight to the cloud' do
    2.times { appliance.dop2(2, 1586) }
    expect(fake.requests.count { it.path.include?('/DOP2/') }).to eq(1)
  end

  it 'names the module host when Dop1 goes through the cloud' do
    appliance.dop1('8E0101000000')
    expect(cloud.requests.find { it.path.end_with?('/DOP/') }.headers['host']).to eq('Miele-0000000000000000.local')
  end

  it 'keeps a local 404 without a cloud account' do
    Miele::Sdk.configure { it.email = nil }
    expect { appliance.dop2(2, 1586) }.to raise_error(Miele::Sdk::NotFoundError)
  end

  it 'reads State locally when the appliance serves it', :aggregate_failures do
    expect(appliance.state.status).to eq(:running)
    expect(cloud.requests).to be_empty
  end

  it 'lists appliances from the account' do
    expect(Miele::Sdk.appliances)
      .to contain_exactly(have_attributes(fab:, host: 'Miele-0000000000000000.local.'))
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
