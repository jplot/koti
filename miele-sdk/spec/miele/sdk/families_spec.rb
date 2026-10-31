# frozen_string_literal: true

RSpec.describe Miele::Sdk::Families do
  let(:fab) { '000123456789' }
  let(:ident) { { 'DeviceType' => 12, 'ProtocolVersion' => 4, 'DeviceIdentLabel' => { 'TechType' => 'H7164BP' } } }
  let(:fake) do
    answer = ident
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: /Ident\z/ } then [200, {}, JSON.generate(answer)]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def family(type, protocol, tech_type = 'X1')
    ident = { 'DeviceType' => type, 'ProtocolVersion' => protocol, 'DeviceIdentLabel' => { 'TechType' => tech_type } }
    described_class.claim(Miele::Sdk::Schema::DeviceIdentification.from(ident))
  end

  it 'gives each family its class, by device type and protocol', :aggregate_failures do
    sdk = Miele::Sdk
    claims = [[12, 4], [18, 2], [14, 2], [7, 4], [1, 4], [2, 2], [17, 4], [19, 201], [25, 2]].map { family(*it) }
    expect(claims).to eq([sdk::Oven, sdk::Hood, sdk::Hob, sdk::Dishwasher, sdk::WashingMachine, sdk::TumbleDryer,
                          sdk::CoffeeMaker, sdk::CoolingAppliance, sdk::WarmingDrawer])
    expect([family(12, 6), family(8, 2, 'G7310'), family(8, 2, 'PG8133')])
      .to eq([sdk::Appliance, sdk::Appliance, sdk::Dishwasher])
  end

  it 'reads Ident once to choose the class', :aggregate_failures do
    oven = Miele::Sdk.appliance('127.0.0.1')
    expect([oven.class, oven.device_type]).to eq([Miele::Sdk::Oven, :oven])
    expect(fake.requests.count { it.path.end_with?('/Ident') }).to eq(1)
  end

  it 'renames the appliance as the app does', :aggregate_failures do
    Miele::Sdk.appliance('127.0.0.1').name = 'Cuisine'
    request = fake.requests.last
    expect([request.verb, request.path, JSON.parse(request.body)])
      .to eq(['PUT', "/Devices/#{fab}/Ident", { 'DeviceName' => 'Cuisine' }])
  end

  context 'with the Miele account' do
    let(:cloud) do
      FakeCloud.start do |request|
        next unless request.path == '/V2/Devices'

        FakeCloud.json([{ host: 'Miele-0000000000000000.local.', devices: [{ mac: fab, ident: }] }])
      end
    end

    before do
      Miele::Sdk.configure do |config|
        config.country = 'FR'
        config.email = 'koti@example.com'
        config.password = 'secret'
        config.locales_host = cloud.url
      end
    end

    after { cloud.stop }

    it 'builds the account appliances from the ident the cloud lists', :aggregate_failures do
      expect(Miele::Sdk.appliances.map(&:class)).to eq([Miele::Sdk::Oven])
      expect(fake.requests).to be_empty
    end
  end
end
