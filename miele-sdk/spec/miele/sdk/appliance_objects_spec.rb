# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { described_class.new('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:select) { ['000f00020629000000000001000107000a'].pack('H*') }
  let(:fake) do
    leaf = select
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

  def sent = fake.requests.map { "#{it.verb} #{it.path.delete_prefix("/Devices/#{fab}/")}" }

  it 'reads and writes through the appliance with the class address', :aggregate_failures do
    value = appliance.object(Miele::Sdk::Objects::Oven::GlobalPsSelect)
    appliance.write_object(value.with(prog_id: :ba_auto_heissluft))
    expect(sent.last(2)).to eq(['GET DOP2/2/1577?idx1=0&idx2=0', 'PUT DOP2/2/1577'])
    expect(fake.requests.last.body.unpack1('H*')).to eq('000f000206290000000000010001070002')
  end

  it 'reads at an address given in place of the one the app computes' do
    appliance.object(Miele::Sdk::Objects::Hood::GlobalSfValue, [2, 105, 9001, 1])
    expect(sent.last).to eq('GET DOP2/2/105?idx1=9001&idx2=1')
  end

  it 'asks for the index the app computes' do
    expect { appliance.object(Miele::Sdk::Objects::Hood::GlobalSfValue) }.to raise_error(ArgumentError, /idx1/)
  end
end
