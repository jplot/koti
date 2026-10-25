# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { described_class.new('127.0.0.1', sleeper: ->(seconds) { naps << seconds }) }

  let(:fab) { '000123456789' }
  let(:naps) { [] }
  let(:dop2_answers) { [] }
  let(:fake) do
    answers = dop2_answers
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET' } then [200, {}, "#{['000e00020631000000000001000104'].pack('H*')}\x07"]
      in { path: /DOP2/ } then answers.shift || [204, {}, '']
      else [200, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def puts_sent = fake.requests.select { it.verb == 'PUT' }.map { it.path.delete_prefix("/Devices/#{fab}/") }

  it 'reads a leaf', :aggregate_failures do
    expect(appliance.dop2(2, 1585).fields).to eq(1 => Miele::Sdk::Dop2::Field[:e8, 7])
    expect(fake.requests.last.path).to eq("/Devices/#{fab}/DOP2/2/1585?idx1=0&idx2=0")
  end

  it 'encodes the appliance state write like the reference', :aggregate_failures do
    appliance.power_on
    request = fake.requests.last
    expect(request).to have_attributes(path: "/Devices/#{fab}/DOP2/2/1586?idx1=0&idx2=0", verified: true)
    expect(request.body.unpack1('H*')).to eq('000e0002063200000000000100010404')
    expect(request.headers['content-length']).to eq('32')
  end

  context 'when the appliance sleeps' do
    let(:dop2_answers) { [[500, {}, '']] }

    it 'wakes a sleeping appliance and retries power on', :aggregate_failures do
      appliance.power_on
      expect(puts_sent).to eq(['DOP2/2/1586?idx1=0&idx2=0', 'State', 'DOP2/2/1586?idx1=0&idx2=0'])
      expect(naps).to eq([3])
    end
  end

  context 'when the appliance stays asleep' do
    let(:dop2_answers) { [[500, {}, '']] * 3 }

    it 'falls back to the switch-off opcode after two wake rounds', :aggregate_failures do
      appliance.power_off
      expect(puts_sent.values_at(0, 2, 4, 5)).to eq(%w[1586 1586 1586 1583].map { "DOP2/2/#{it}?idx1=0&idx2=0" })
      expect(fake.requests.last.body.unpack1('H*')).to eq('00100001062f0000000000010001070013')
    end
  end

  context 'when the appliance refuses the state write' do
    let(:dop2_answers) { [[404, {}, '']] }

    it 'falls back to the switch-on opcode at once' do
      appliance.power_on
      expect(puts_sent).to eq(%w[1586 1583].map { "DOP2/2/#{it}?idx1=0&idx2=0" })
    end
  end
end
