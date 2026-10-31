# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hood do
  subject(:hood) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => 2) }
  let(:supported) { { 34 => [0x00, 0b0000_0101], 37 => [0b0000_0010, 0b0000_1000] } }
  let(:state) { { 'Status' => 4, 'Light' => 2, 'ExtendedState' => extended(supported) } }
  let(:fake) do
    served = state
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(served)]
      in { verb: 'POST', body: /12010100019c5c/ } then [200, {}, '{"Response":"12011100019c5c00000087"}']
      in { verb: 'POST', body: /8E0A01/ } then [200, {}, '{"Response":"8E0A1100010201000700163c00"}']
      else [200, {}, '{}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def extended(bytes)
    data = Array.new(73, 0)
    bytes.each { |index, value| Array(value).each_with_index { |byte, offset| data[index + offset] = byte } }
    data.pack('C*').unpack1('H*')
  end

  def writes
    requests = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Request') }
    requests.reject { it.start_with?('12010100019c5c', '8E0A01') }
  end

  it 'switches the ambient light with 8E11 as the app does' do
    hood.ambient_light = true
    hood.ambient_light = false
    expect(writes).to eq(%w[8E11020001020200000000000003e803e8 8E11020001020100000000000000000000])
  end

  it 'configures the ambient light with 8E10' do
    hood.configure_ambient_light(mode: :ambient, rgb: [255, 128, 0], brightness: 500, colour_temperature: 300)
    expect(writes).to eq(['8E100200010100ff0080000001f4012c'])
  end

  it 'switches the ambient light while cooking with PF 40029' do
    hood.ambient_light_while_cooking = true
    expect(writes).to eq(['12010200019c5d00000001'])
  end

  it 'resets the grease filter with PF 40012 in structure version 1, the charcoal one with 40013' do
    hood.reset_grease_filter
    hood.reset_charcoal_filter
    expect(writes).to eq(%w[12010200019c4c00000001 12010200019c4d00000001])
  end

  it 'sets dehumidification regulated or off with PF 40025, never controlled', :aggregate_failures do
    hood.dehumidification = :regulated
    hood.dehumidification = :off
    expect { hood.dehumidification = :controlled }.to raise_error(ArgumentError)
    expect(writes).to eq(%w[12010200019c5900000002 12010200019c5900000000])
  end

  it 'makes the dehumidification blower silent by rewriting what 8E0A reads', :aggregate_failures do
    hood.dehumidification_silent = true
    reads = fake.requests.map { JSON.parse(it.body)['Request'] if it.verb == 'POST' }.compact
    expect(reads).to eq(%w[8E0A0100010201 8E0A020001020101000700163c])
  end

  it 'starts and stops the fragrance with ProcessAction 1100, and sets the Miele program' do
    hood.fragrance(:start)
    hood.fragrance(:stop)
    hood.fragrance(:miele_program)
    expect(writes).to eq(%w[110002000134 110002000135 12010200019c5a00000000 110002000135 12010200019c5a00000001])
  end

  it 'starts grease melting with 1406 and delays it with 8E18' do
    hood.grease_melting = true
    hood.grease_melting = false
    hood.grease_melting_at(90)
    expect(writes).to eq(%w[14060200010100 14060200010000 8E18020001005a])
  end

  it 'switches auto refresh with PF 40023' do
    hood.auto_refresh = true
    expect(writes).to eq(['12010200019c5700000001'])
  end

  context 'when the hood is off' do
    let(:state) { { 'Status' => 1, 'Light' => 2, 'ExtendedState' => '' } }

    it 'asks to wake a hood that is off before what depends on its state', :aggregate_failures do
      [-> { hood.fan_level = 2 }, -> { hood.grease_melting = true }, -> { hood.auto_refresh = true }]
        .each { expect(&it).to raise_error(Miele::Sdk::ActionUnavailableError, /wake/) }
      expect(writes).to be_empty
    end

    it 'wakes a sleeping Dop1 hood by writing back its Light' do
      hood.wake
      request = fake.requests.last
      expect([request.verb, request.path, JSON.parse(request.body)])
        .to eq(['PUT', "/Devices/#{fab}/State", { 'Light' => 2 }])
    end
  end

  context 'when the hood supports none of them' do
    let(:supported) { {} }

    it 'refuses what the hood does not support, as the app hides it', :aggregate_failures do
      [-> { hood.ambient_light = true }, -> { hood.dehumidification = :off }, -> { hood.grease_melting = true },
       -> { hood.auto_refresh = true }].each { expect(&it).to raise_error(Miele::Sdk::ActionUnavailableError) }
      expect(writes).to be_empty
    end
  end

  context 'with a DOP2 hood' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => 4) }

    it 'refuses a Dop1 action' do
      expect { hood.grease_melting = true }.to raise_error(Miele::Sdk::ActionUnavailableError, /Dop1/)
    end
  end
end
