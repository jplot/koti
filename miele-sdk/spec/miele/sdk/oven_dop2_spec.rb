# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:appliance) { described_class.new('127.0.0.1', sleeper: ->(seconds) { naps << seconds }, ident:) }

  let(:fab) { '000123456789' }
  let(:naps) { [] }
  let(:dop2_answers) { [] }
  let(:ident) do
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4,
                                                  'DeviceIdentLabel' => { 'TechType' => tech_type })
  end
  let(:fake) do
    answers = dop2_answers
    state = state_answer
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then state
      in { verb: 'GET' } then [200, {}, "#{['000e00020631000000000001000104'].pack('H*')}\x07"]
      in { path: /DOP2/ } then answers.shift || [204, {}, '']
      else [200, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def puts_sent = fake.requests.select { it.verb == 'PUT' }.map { it.path.delete_prefix("/Devices/#{fab}/") }

  def tech_type = 'H7464BP'

  def remote_enable = [15, 0, 0]

  def state_answer = [200, {}, JSON.generate('Status' => 1, 'RemoteEnable' => remote_enable)]

  def power_written = fake.requests.select { it.verb == 'PUT' }.map { it.body.unpack1('H*') }

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

  context 'with a Dop1 oven' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 2) }

    it 'neither switches on nor off, as the app has no switch action for it', :aggregate_failures do
      expect { appliance.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { appliance.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(puts_sent).to be_empty
    end
  end

  context 'with an H2 oven' do
    def tech_type = 'H2861BP'

    it 'switches off but never on, as the app does', :aggregate_failures do
      expect { appliance.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
      appliance.power_off
      expect(power_written).to eq(['000e0002063200000000000100010401'])
    end
  end

  context 'without remote control or mobile start' do
    def remote_enable = [0, 0, 0]

    it 'neither switches on nor off', :aggregate_failures do
      expect { appliance.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { appliance.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(puts_sent).to be_empty
    end
  end

  context 'with local control' do
    def remote_enable = [7, 0, 0]

    it 'switches on but not off', :aggregate_failures do
      appliance.power_on
      expect { appliance.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(power_written).to eq(['000e0002063200000000000100010404'])
    end
  end

  context 'with mobile start alone' do
    def remote_enable = [0, 0, 1]

    it 'switches on and off, as the app offers both', :aggregate_failures do
      appliance.power_on
      appliance.power_off
      expect(power_written).to eq(%w[000e0002063200000000000100010404 000e0002063200000000000100010401])
    end
  end

  context 'when the oven is not connected' do
    def state_answer = [200, {}, JSON.generate('Status' => 255, 'RemoteEnable' => [15, 0, 0])]

    it 'does not switch off, as the app disables its settings switch', :aggregate_failures do
      expect { appliance.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError, /not connected/)
      expect(puts_sent).to be_empty
    end
  end

  context 'when State answers 500' do
    def state_answer = [500, {}, '']

    it 'raises without switching off, the app swallowing a 500 on the write alone', :aggregate_failures do
      expect { appliance.power_off }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
      expect(puts_sent).to be_empty
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
