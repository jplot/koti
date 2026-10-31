# frozen_string_literal: true

RSpec.describe Miele::Sdk::CoffeeMaker do
  subject(:coffee) { maker(tech_type) }

  let(:fab) { '000123456789' }
  let(:tech_type) { 'CVA 7440' }
  let(:leaves) { {} }
  let(:fake) do
    served = leaves
    FakeAppliance.start do |request|
      case request
      in { path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/DOP2/(\d+)/(\d+)(?:\?idx1=(\d+)&idx2=(\d+))?\z} }
        unit, attribute, idx1, idx2 = Regexp.last_match.captures.map(&:to_i)
        [200, {}, served.fetch([unit, attribute, idx1, idx2]) { dop2_leaf(unit, attribute, {}, idx1:, idx2:) }]
      in { verb: 'POST' } then [200, {}, '{"Response":"10001101"}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def maker(tech, protocol: 4)
    ident = Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 17, 'ProtocolVersion' => protocol,
                                                          'DeviceIdentLabel' => { 'TechType' => tech })
    described_class.new('127.0.0.1', ident:)
  end

  def dop2_paths = fake.requests.map(&:path).grep(/DOP2/).map { it.delete_prefix("/Devices/#{fab}/DOP2/") }

  it 'tells its variant from the TechType and protocol, as the app does' do
    variants = [['CM 7550'], ['CM6360'], ['CM6365'], ['CVA 7440'], ['CVA7840'], ['CVA6805', { protocol: 2 }],
                ['CVA6805']].map { |tech, options| maker(tech, **options.to_h).variant }
    expect(variants).to eq(%i[cm7 cm6f unknown cva_ref2 cva cva6000 unknown])
  end

  it 'reads the CM7 context on unit 2 and the others on unit 1', :aggregate_failures do
    [maker('CM7550'), coffee].each do |appliance|
      appliance.program_context
      appliance.context
      appliance.notifications
    end
    expect(dop2_paths).to eq(%w[2/1574?idx1=0&idx2=1 2/1585?idx1=0&idx2=8 2/131?idx1=0&idx2=1
                                1/1574?idx1=0&idx2=1 1/1585?idx1=0&idx2=8 1/131?idx1=0&idx2=1])
  end

  it 'reads a drink at idx1 = its id, idx2 = 0, and its limits the same way' do
    coffee.drink(24_005)
    coffee.drink_limits(24_005)
    expect(dop2_paths).to eq(%w[2/261?idx1=24005&idx2=0 2/331?idx1=24005&idx2=0])
  end

  it 'reads cleaning, descaling, features and ident where the app does', :aggregate_failures do
    expect([coffee.cleaning, coffee.descaling, coffee.features, coffee.device_ident].map(&:class))
      .to eq([Miele::Sdk::Objects::CoffeeGen7::GlobalCleaningInformationCO,
              Miele::Sdk::Objects::CoffeeGen7::GlobalDescalingInformationCO,
              Miele::Sdk::Objects::CoffeeGen7::GlobalFeatureList, Miele::Sdk::Objects::CoffeeGen7::GlobalDeviceIdent])
    expect(dop2_paths).to eq(%w[2/289?idx1=0&idx2=1 2/288?idx1=0&idx2=3 2/348?idx1=0&idx2=0 2/144?idx1=0&idx2=0])
  end

  context 'with a CM7' do
    let(:tech_type) { 'CM7550' }

    it 'reads none of what the app reads only on the others', :aggregate_failures do
      expect([coffee.cleaning, coffee.descaling, coffee.features, coffee.device_ident]).to all(be_nil)
      expect(coffee.profiles).to eq({})
      expect(dop2_paths).to be_empty
    end
  end

  it 'reads the profiles along their chain from the standard one' do
    leaves[[1, 109, 24_812, 0]] = dop2_leaf(1, 109, { 3 => dop2_field(:string, 'Miele') }, idx1: 24_812, idx2: 24_813)
    leaves[[1, 109, 24_813, 0]] = dop2_leaf(1, 109, { 3 => dop2_field(:string, 'Anna') }, idx1: 24_813, idx2: 24_813)
    expect(coffee.profiles.transform_values(&:name)).to eq(24_812 => 'Miele', 24_813 => 'Anna')
  end

  context 'with a CVA6000' do
    subject(:coffee) { maker('CVA6805', protocol: 2) }

    it 'reads its state on 1000 and its usage counters on 8D00' do
      coffee.device_state
      coffee.usage_counters
      expect(fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body)['Request'] })
        .to eq(%w[10000100 8D000100])
    end
  end
end
