# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:fake) do
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def written
    fake.requests.select { it.verb == 'PUT' }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body.unpack1('H*')] }
  end

  it 'answers a query as the app does' do
    oven.acknowledge(:query, 4, option: 12)
    expect(written).to eq([['DOP2/2/138',
                            '00240002008a000000000005000107000000020700000003080000000000040700040005040c']])
  end

  it 'answers on 5/138 for the second cavity' do
    oven.acknowledge(:info, 14, option: 1, second_cavity: true)
    expect(written).to eq([['DOP2/5/138',
                            '00240005008a000000000005000107000e000207000000030800000000000407000000050401']])
  end

  it 'takes the id and the option as the notification lists them' do
    oven.acknowledge(:message, Miele::Sdk::Objects::Oven::GlobalEnumNtfctnMessageId.from(20), option: :ok)
    expect(written.map(&:last)).to eq(['00240002008a0000000000050001070000000207001400030800000000000407000000050401'])
  end

  context 'with a Dop1 oven' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 12, 'ProtocolVersion' => 2) }

    it 'refuses a Dop1 oven' do
      expect { oven.acknowledge(:query, 4, option: 12) }.to raise_error(Miele::Sdk::ActionUnavailableError, /Dop1/)
    end
  end
end
