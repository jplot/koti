# frozen_string_literal: true

RSpec.describe Miele::Sdk::ObjectAccess do
  subject(:appliance) { Miele::Sdk::Dishwasher.new('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:combi) { Miele::Sdk::Objects::Dishwasher::GlobalDeviceCombiState }
  let(:fields) { { 1 => dop2_field(:e8, 4), 3 => dop2_field(:e8, 7) } }
  let(:fake) do
    leaf = dop2_leaf(2, 1586, fields, idx2: 1)
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET' } then [200, {}, leaf]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def puts_sent = fake.requests.select { it.verb == 'PUT' }

  it 'reads, changes and writes back a leaf where it read it', :aggregate_failures do
    appliance.modify(combi, [2, 1586, 0, 1]) { it.with(appliance_state: :off) }
    expect(fake.requests.map(&:path).last(2))
      .to eq(%W[/Devices/#{fab}/DOP2/2/1586?idx1=0&idx2=1 /Devices/#{fab}/DOP2/2/1586])
    expect(puts_sent.last.body.unpack1('H*')).to eq(dop2_leaf(2, 1586, fields.merge(1 => dop2_field(:e8, 1)),
                                                              idx2: 1).unpack1('H*'))
  end

  it 'writes back the indexes the appliance answered, as the dishwasher and laundry modules do' do
    appliance.modify(combi, [2, 1586, 0, 0]) { it.with(appliance_state: :off) }
    expect(puts_sent.last.body.unpack1('H*')).to eq(dop2_leaf(2, 1586, fields.merge(1 => dop2_field(:e8, 1)),
                                                              idx2: 1).unpack1('H*'))
  end

  context 'when the leaf lacks the member to change' do
    let(:fields) { { 3 => dop2_field(:e8, 7) } }

    it 'writes nothing when the leaf lacks the member to change', :aggregate_failures do
      expect { appliance.modify(combi, [2, 1586, 0, 1]) { it.with(appliance_state: :off) } }
        .to raise_error(ArgumentError)
      expect(puts_sent).to be_empty
    end
  end

  it 'refuses an action before sending anything', :aggregate_failures do
    refusing = Class.new(Miele::Sdk::Appliance) { def act = require!(false, 'remote control is off') }
    expect { refusing.new('127.0.0.1').act }.to raise_error(Miele::Sdk::ActionUnavailableError, 'remote control is off')
    expect(fake.requests).to be_empty
  end
end
