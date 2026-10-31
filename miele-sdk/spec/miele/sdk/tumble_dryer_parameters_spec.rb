# frozen_string_literal: true

RSpec.describe Miele::Sdk::TumbleDryer do
  subject(:dryer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 2, 'ProtocolVersion' => 4) }
  let(:leaves) { {} }
  let(:fake) do
    served = leaves
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate('Status' => 3, 'RemoteEnable' => [15, 0, 1])]
      in { verb: 'GET', path: %r{/DOP2/2/1574} } then [200, {}, ps_context]
      in { verb: 'GET', path: %r{/DOP2/2/1577} } then [200, {}, served.fetch(1577) { select }]
      in { verb: 'POST', body: /"86020100"/ } then [200, {}, JSON.generate(Response: "86021101#{status}")]
      in { verb: 'POST' } then [200, {}, '{"Response":"86021201"}']
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def struct(fields) = dop2_field(:struct, fields)

  def ps_context
    para = { 6 => struct({ 6 => struct({ 2 => dop2_field(:bool, true) }) }) }
    dop2_leaf(2, 1574, { 2 => struct(para), 6 => struct({ 1 => dop2_field(:e16, 5) }) }, idx2: 1)
  end

  def select(prog: 0, type: 0, **given)
    values = { moisture: 4, minutes: 0, eco: false, anti_crease: false }.merge(given)
    extras = { 6 => dop2_field(:bool, values[:eco]), 7 => dop2_field(:bool, values[:anti_crease]) }
    para = { 3 => dop2_field(:u16, values[:moisture]), 4 => dop2_field(:u16, values[:minutes]), 6 => struct(extras) }
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, prog), 3 => dop2_field(:e8, type), 5 => struct(para) })
  end

  def status = "021c0000000000000003000000000000000100#{'00' * 37}"

  def written = fake.requests.reject { it.verb == 'GET' }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body] }

  it 'writes the extras, the drying level as its flag and the drying time on 2/1577' do
    dryer.set_parameters(extras: [:anti_crease], drying_level: :cupboard_dry, drying_time: 90)
    expect(written).to eq([['DOP2/2/1577', select(prog: 5, type: 2, moisture: 16, minutes: 90, anti_crease: true)]])
  end

  context 'with a SmartBiz dryer' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 2, 'ProtocolVersion' => 4,
                                                    'DeviceIdentLabel' => { 'TechType' => 'PDR510' })
    end

    it 'writes iron dry as 4, as the app converts it' do
      dryer.set_parameters(drying_level: :iron_dry)
      expect(written.last.last).to eq(select(prog: 5, type: 2, moisture: 4, eco: true))
    end
  end

  it 'refuses extras when 2/1577 carries none, sending nothing', :aggregate_failures do
    leaves[1577] = dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 0), 5 => struct({ 3 => dop2_field(:u16, 4) }) })
    expect { dryer.set_parameters(extras: [:eco]) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'writes iron dry as its flag on any other dryer' do
    dryer.set_parameters(drying_level: :iron_dry)
    expect(written.last.last).to eq(select(prog: 5, type: 2, moisture: 256, eco: true))
  end

  context 'with a Dop1 dryer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 2, 'ProtocolVersion' => 2) }

    it 'copies the status of 8602, then writes the extras, the drying level step and the drying time' do
      dryer.set_parameters(extras: [:anti_crease], drying_level: :hand_iron, drying_time: 45)
      expect(written.map { JSON.parse(it.last).fetch('Request') })
        .to eq(['86020100', %w[86020100021c0000000000000004 2d00 000000000000 01].join])
    end

    it 'writes 255 for a drying level the app has no step for' do
      dryer.set_parameters(drying_level: :deficiency_dry)
      expect(JSON.parse(written.last.last).fetch('Request')[26, 2]).to eq('ff')
    end
  end
end
