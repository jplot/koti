# frozen_string_literal: true

RSpec.describe Miele::Sdk::TumbleDryer do
  subject(:dryer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:protocol) { 4 }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 2, 'ProtocolVersion' => protocol) }
  let(:fake) do
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET' } then [200, {}, dop2_leaf(2, 1585, { 6 => dop2_field(:struct, { 1 => dop2_field(:e8, 2) }) })]
      in { verb: 'POST' } then [200, {}, '{"Response":"86001100"}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  it 'reads a closed DOP2 dryer door as locked, as the app does' do
    expect(dryer.door).to eq(:locked)
  end

  context 'with a Dop1 dryer' do
    let(:protocol) { 2 }

    it 'reads its program list from 8600 and its selection from 8601' do
      dryer.program_list
      dryer.selection
      expect(fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body)['Request'] })
        .to eq(%w[86000100 86010100])
    end
  end
end
