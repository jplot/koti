# frozen_string_literal: true

RSpec.describe Miele::Sdk::CoffeeMaker do
  subject(:coffee) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { waits << seconds }) }

  let(:fab) { '000123456789' }
  let(:ident) { identity('CVA 7440', 4) }
  let(:waits) { [] }
  let(:served) do
    { 'State' => { 'Status' => 2, 'RemoteEnable' => [15, 0, 1] }, [1, 1574, 0, 1] => ps_context(0, 0),
      [2, 1586, 0, 0] => combi(2, 0), [2, 17, 0, 0] => software_id(2, 6228), [1, 17, 0, 0] => software_id(1, 6227),
      [2, 1577, 0, 1] => select(0, 0), [2, 1583, 0, 1] => dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) }, idx2: 1),
      [2, 138, 0, 1] => acknowledgement(0, 0, 0), 'DOP' => '{"Response":"11011201"}' }
  end
  let(:fake) do
    answers = served
    FakeAppliance.start do |request|
      case request
      in { path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/DOP2/} } if answers.delete(:asleep) then [500, {}, '']
      in { verb: 'GET', path: %r{/DOP2/(\d+)/(\d+)\?idx1=(\d+)&idx2=(\d+)\z} }
        key = Regexp.last_match.captures.map(&:to_i)
        [200, {}, answers.fetch(key) { dop2_leaf(key[0], key[1], {}, idx1: key[2], idx2: key[3]) }]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(answers['State'])]
      in { verb: 'POST' } then [200, {}, answers['DOP']]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def identity(tech, protocol)
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 17, 'ProtocolVersion' => protocol,
                                                  'DeviceIdentLabel' => { 'TechType' => tech })
  end

  def struct(fields) = dop2_field(:struct, fields)

  def ps_context(prog, phase, unit: 1, missing: [], sub: 0)
    attributes = { 1 => dop2_field(:e16, phase), 2 => dop2_field(:e16, sub), 3 => struct({}), 10 => dop2_field(:e8, 0),
                   28 => dop2_field(:e16, prog) }
    dop2_leaf(unit, 1574, { 7 => struct(attributes.except(*missing)) }, idx2: 1)
  end

  def combi(appliance, operation)
    dop2_leaf(2, 1586, { 1 => dop2_field(:e8, appliance), 2 => dop2_field(:e8, operation),
                         3 => dop2_field(:e8, 0) })
  end

  def software_id(unit, id) = dop2_leaf(unit, 17, { 2 => dop2_field(:struct_array, [{ 1 => dop2_field(:u32, id) }]) })

  def select(prog, type, two: false, double: false, attribute: 1577)
    para = { 1 => dop2_field(:bool, double), 2 => dop2_field(:bool, two) }
    dop2_leaf(2, attribute, { 1 => dop2_field(:e16, prog), 3 => dop2_field(:e8, type), 8 => struct(para) }, idx2: 1)
  end

  def acknowledgement(info, query, option, attribute: 138)
    dop2_leaf(2, attribute, { 1 => dop2_field(:e16, info), 4 => dop2_field(:e16, query),
                              5 => dop2_field(:e8, option) }, idx2: 1)
  end

  def written
    fake.requests.reject { %w[GET POST].include?(it.verb) }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body] }
  end

  def dop1_requests = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Request') }

  it 'brews a drink for two cups as the app does, the header naming idx1' do
    coffee.brew(24_005, two_cups: true)
    expect(written).to eq([['DOP2/2/1577?idx1=0&idx2=1', select(24_005, 0, two: true, attribute: 0)]])
  end

  it 'refuses a drink while 1/1574 lacks a member the app reads', :aggregate_failures do
    served[[1, 1574, 0, 1]] = ps_context(0, 0, missing: [2])
    expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'refuses program 0 or an id the app does not define, before sending anything', :aggregate_failures do
    expect { coffee.brew(0) }.to raise_error(ArgumentError)
    expect { coffee.brew(999_999) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'refuses the double shot the software ids do not allow', :aggregate_failures do
    served[[1, 17, 0, 0]] = software_id(1, 6226)
    expect { coffee.brew(24_005, double_shot: true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'refuses to brew while a query shows, as the app does' do
    served[[1, 131, 0, 1]] = dop2_leaf(1, 131, { 4 => dop2_field(:struct_array, [{ 1 => dop2_field(:e16, 3) }]) },
                                       idx2: 1)
    expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'refuses to brew while a drink is dispensing' do
    served[[1, 1574, 0, 1]] = ps_context(24_010, 0)
    expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'brews once the drink running has reached its phase 10003' do
    served[[1, 1574, 0, 1]] = ps_context(24_010, 10_003)
    coffee.brew(24_005)
    expect(written.size).to eq(1)
  end

  it 'refuses to brew while Barista or a care program runs', :aggregate_failures do
    served[[1, 1574, 0, 1]] = ps_context(24_407, 0)
    expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    served[[1, 1574, 0, 1]] = ps_context(0, 0)
    served[[2, 1586, 0, 0]] = combi(2, 8)
    expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'refuses to brew without mobile start' do
    served['State'] = { 'Status' => 2, 'RemoteEnable' => [15, 0, 0] }
    expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'starts Barista when the coffee maker lists it among its special beverages', :aggregate_failures do
    expect { coffee.start_barista }.to raise_error(Miele::Sdk::ActionUnavailableError)
    group = { 1 => dop2_field(:u16, 24_400), 4 => dop2_field(:u32_array, [0x80]) }
    served[[1, 1599, 0, 1]] = dop2_leaf(1, 1599, { 1 => dop2_field(:struct_array, [group]) }, idx2: 1)
    coffee.start_barista
    expect(written).to eq([['DOP2/2/1577?idx1=0&idx2=1', select(24_407, 0, attribute: 0)]])
  end

  context 'when the coffee maker lists Barista' do
    before do
      group = { 1 => dop2_field(:u16, 24_400), 4 => dop2_field(:u32_array, [0x80]) }
      served[[1, 1599, 0, 1]] = dop2_leaf(1, 1599, { 1 => dop2_field(:struct_array, [group]) }, idx2: 1)
    end

    it "starts Barista without mobile start, as the app's entry point allows" do
      served['State'] = { 'Status' => 2, 'RemoteEnable' => [15, 0, 0] }
      coffee.start_barista
      expect(written.size).to eq(1)
    end

    it 'refuses Barista while any program runs' do
      served[[1, 1574, 0, 1]] = ps_context(24_500, 0)
      expect { coffee.start_barista }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  it 'stops a running drink with request 2 on 2/1583 at 0/1, the header naming idx1' do
    served[[1, 1574, 0, 1]] = ps_context(24_010, 0)
    coffee.stop
    expect(written).to eq([['DOP2/2/1583?idx1=0&idx2=1', dop2_leaf(2, 0, { 1 => dop2_field(:e16, 2) }, idx2: 1)]])
  end

  it 'stops no drink cancelled, done or not a drink, as the app hides its stop button', :aggregate_failures do
    [ps_context(24_010, 0, sub: 24_057), ps_context(24_010, 10_003), ps_context(24_407, 0)].each do |context|
      served[[1, 1574, 0, 1]] = context
      expect { coffee.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
    expect(written).to be_empty
  end

  it 'stops nothing under local control or during care', :aggregate_failures do
    served[[1, 1574, 0, 1]] = ps_context(24_010, 0)
    served['State'] = { 'Status' => 5, 'RemoteEnable' => [7, 0, 1] }
    expect { coffee.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
    served['State'] = { 'Status' => 5, 'RemoteEnable' => [15, 0, 1] }
    served[[2, 1586, 0, 0]] = combi(2, 8)
    expect { coffee.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'refuses an option the app does not map, before reading anything', :aggregate_failures do
    expect { coffee.acknowledge(:message, option: 0) }.to raise_error(ArgumentError)
    expect { coffee.acknowledge(:message, option: 18) }.to raise_error(ArgumentError)
    expect(fake.requests.map(&:path).grep(%r{/DOP2/2/138})).to be_empty
  end

  it 'acknowledges with the PIN code option, the last the app maps on a Gen7' do
    coffee.acknowledge(:message, option: :pincode)
    expect(written.map(&:last)).to eq([acknowledgement(0, 0, 17, attribute: 0)])
  end

  it 'acknowledges a query with its id, a message with its option only' do
    coffee.acknowledge(:query, 3, option: 2)
    coffee.acknowledge(:message, 9, option: 1)
    expect(written.map(&:last)).to eq([acknowledgement(0, 3, 2, attribute: 0), acknowledgement(0, 0, 1, attribute: 0)])
  end

  context 'when it is off' do
    before { served['State'] = { 'Status' => 1, 'RemoteEnable' => [15, 0, 1] } }

    it 'wakes a coffee maker that answers 500 to its first DOP2 read, with DeviceAction 2', :aggregate_failures do
      served[:asleep] = true
      served[[2, 1586, 0, 0]] = combi(1, 0)
      coffee.power_on
      expect(written.map(&:first)).to eq(%w[State DOP2/2/1586])
      expect(written.last.last).to eq(combi(4, 0))
      expect(waits).to eq([5, 1.5])
    end

    it 'writes nothing when 2/1586 already shows it on' do
      served[[2, 1586, 0, 0]] = combi(4, 0)
      coffee.power_on
      expect(written).to be_empty
    end

    it 'refuses to switch off a coffee maker that is off' do
      expect { coffee.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  it 'refuses to switch off while Barista runs, or under local control, as the app does', :aggregate_failures do
    served[[1, 1574, 0, 1]] = ps_context(24_407, 0)
    expect { coffee.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
    served[[1, 1574, 0, 1]] = ps_context(0, 0)
    served['State'] = { 'Status' => 2, 'RemoteEnable' => [7, 0, 1] }
    expect { coffee.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'refuses to switch on a coffee maker that is on, as the app switches it off then' do
    expect { coffee.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'switches off with ApplianceState 1, written as read without an index' do
    coffee.power_off
    expect(written).to eq([['DOP2/2/1586', combi(1, 0)]])
  end

  context 'with a CM7' do
    let(:ident) { identity('CM7550', 4) }

    before do
      served[[2, 1574, 0, 1]] = ps_context(24_100, 0, unit: 2)
      served[[2, 17, 0, 0]] = software_id(2, 5374)
    end

    it 'brews a double shot past its own drinks, with the software id of 2/17 alone', :aggregate_failures do
      coffee.brew(24_005, double_shot: true)
      expect(written.size).to eq(1)
      expect(fake.requests.map(&:path).grep(%r{/DOP2/1/17})).to be_empty
    end

    it 'brews during a care program 24060, which the app does not count as care' do
      served[[2, 1574, 0, 1]] = ps_context(24_060, 0, unit: 2)
      served[[2, 1586, 0, 0]] = combi(2, 8)
      coffee.brew(24_005)
      expect(written.size).to eq(1)
    end

    it 'refuses option 17, which its acknowledgements stop short of' do
      expect { coffee.acknowledge(:message, option: 17) }.to raise_error(ArgumentError)
    end

    it 'refuses to brew while one of its drinks runs' do
      served[[2, 1574, 0, 1]] = ps_context(24_010, 0, unit: 2)
      expect { coffee.brew(24_005) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with an unknown DOP2 coffee maker' do
    let(:ident) { identity('CM 9000', 4) }

    it 'refuses to switch it on, as the app does' do
      expect { coffee.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with a CVA6000' do
    let(:ident) { identity('CVA6805', 2) }

    it 'acknowledges nothing on a CVA6000', :aggregate_failures do
      expect { coffee.acknowledge(:query, 3, option: 2) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(fake.requests.reject { it.verb == 'GET' }).to be_empty
    end

    it 'switches off on 1101 and stops a running drink on 1100' do
      coffee.power_off
      served['State'] = { 'Status' => 5, 'RemoteEnable' => [15, 0, 1] }
      coffee.stop
      expect(dop1_requests).to eq(%w[110102000103 110002000102])
    end

    it 'switches its light by writing back its State' do
      served['State'] = { 'Status' => 2, 'RemoteEnable' => [15, 0, 1], 'Light' => 2 }
      coffee.light = true
      expect(written.map { [it.first, JSON.parse(it.last)] })
        .to eq([['State', { 'Status' => 2, 'RemoteEnable' => [15, 0, 1], 'Light' => 1 }]])
    end

    it 'leaves out of that State the keys the app does not know, as its DeviceStateDto does' do
      served['State'] = { 'Status' => 2, 'RemoteEnable' => [15, 0, 1], 'Light' => 2, 'ProgramName' => 'Espresso' }
      coffee.light = true
      expect(JSON.parse(written.last.last)).not_to have_key('ProgramName')
    end
  end
end
