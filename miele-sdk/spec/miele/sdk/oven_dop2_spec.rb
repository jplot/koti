# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
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

  it 'reads a DOP2 leaf without a query unless given an index', :aggregate_failures do
    expect(appliance.dop2(2, 1585).fields).to eq(1 => Miele::Sdk::Dop2::Field[:e8, 7])
    appliance.dop2(1, 131, idx1: 0, idx2: 1)
    expect(fake.requests.map(&:path).last(2))
      .to eq(%W[/Devices/#{fab}/DOP2/2/1585 /Devices/#{fab}/DOP2/1/131?idx1=0&idx2=1])
  end

  it 'writes a DOP2 leaf without a query', :aggregate_failures do
    appliance.power_on
    request = fake.requests.last
    expect(request).to have_attributes(path: "/Devices/#{fab}/DOP2/2/1586", verified: true)
    expect(request.body.unpack1('H*')).to eq('000e0002063200000000000100010404')
    expect(request.headers['content-length']).to eq('32')
  end

  it "writes the index in the path when asked, as the app's hood and coffee modules do" do
    appliance.write_dop2(Miele::Sdk::Dop2::Leaf.new(unit: 2, attribute: 1583, idx1: 1, idx2: 1, fields: {}),
                         with_index: true)
    expect(puts_sent).to eq(['DOP2/2/1583?idx1=1&idx2=1'])
  end

  it 'switches off with one write' do
    appliance.power_off
    expect(puts_sent).to eq(['DOP2/2/1586'])
  end

  context 'when the appliance sleeps' do
    let(:dop2_answers) { [[500, {}, '']] }

    it 'switches on like the app: state 4, then DeviceAction 2 and a retry on 500', :aggregate_failures do
      appliance.power_on
      expect(puts_sent).to eq(%w[DOP2/2/1586 State DOP2/2/1586])
      expect(naps).to eq([3])
    end

    it 'switches off despite a 500, as the app does', :aggregate_failures do
      expect { appliance.power_off }.not_to raise_error
      expect(puts_sent).to eq(['DOP2/2/1586'])
    end
  end

  context 'when the appliance stays asleep' do
    let(:dop2_answers) { [[500, {}, '']] * 3 }

    it 'gives up after three attempts without any user request', :aggregate_failures do
      expect { appliance.power_on }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
      expect(puts_sent).to eq(%w[DOP2/2/1586 State DOP2/2/1586 State DOP2/2/1586])
    end
  end
end
