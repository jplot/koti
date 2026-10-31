# frozen_string_literal: true

RSpec.describe Miele::Sdk::WashingMachine do
  subject(:washer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:protocol) { 4 }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => protocol) }
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      in { verb: 'POST' } then [200, {}, '{"Response":"82001100010203"}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def paths = fake.requests.map { it.path.delete_prefix("/Devices/#{fab}/") }

  it 'reads the laundry context without an index, and the program context at idx 0/1', :aggregate_failures do
    resources['DOP2/2/1585'] = dop2_leaf(2, 1585, {})
    resources['DOP2/2/1574?idx1=0&idx2=1'] = dop2_leaf(2, 1574, {}, idx2: 1)
    resources['DOP2/2/131?idx1=0&idx2=1'] = dop2_leaf(2, 131, {}, idx2: 1)
    resources['DOP2/2/105?idx1=12037&idx2=1'] = dop2_leaf(2, 105, { 4 => dop2_field(:i16, 1) }, idx1: 12_037, idx2: 1)
    objects = Miele::Sdk::Objects::Laundry
    expect([washer.context, washer.program_context, washer.notifications].map(&:class))
      .to eq([objects::GlobalDeviceContext, objects::GlobalPsContext, objects::GlobalNtfctnShow])
    expect(washer.anti_crease.current_value).to eq(1)
  end

  it 'reads the program list page by page, as the app does', :aggregate_failures do
    resources['DOP2/2/1584?idx1=1&idx2=1'] = dop2_leaf(2, 1584, {}, idx1: 1, idx2: 2)
    resources['DOP2/2/1584?idx1=1&idx2=513'] = dop2_leaf(2, 1584, {}, idx1: 513, idx2: 513)
    expect(washer.programs.size).to eq(2)
    expect(paths.grep(/1584/)).to eq(%w[DOP2/2/1584?idx1=1&idx2=1 DOP2/2/1584?idx1=1&idx2=513])
  end

  it 'reads the door of a DOP2 washer from 2/1585' do
    resources['DOP2/2/1585'] = dop2_leaf(2, 1585, { 6 => dop2_field(:struct, { 1 => dop2_field(:e8, 3) }) })
    expect(washer.door).to eq(:locked)
  end

  it 'reads the TwinDos trays from services' do
    resources['services'] = JSON.generate('TwinDos' => { 'Trays' => [] })
    expect(washer.twin_dos).to eq('Trays' => [])
  end

  context 'with a Dop1 washer' do
    let(:protocol) { 2 }

    def serve(bytes, state = {})
      data = Array.new(67, 0)
      bytes.each { |index, value| Array(value).each_with_index { |byte, offset| data[index + offset] = byte } }
      resources['State'] = JSON.generate({ 'Status' => 5, 'ExtendedState' => data.pack('C*').unpack1('H*') }
                                           .merge(state))
    end

    it 'reads the door from SignalDoor, as the app does', :aggregate_failures do
      serve({}, 'SignalDoor' => true)
      expect(washer.door).to eq(:open)
      serve({}, 'SignalDoor' => false)
      expect(washer.door).to eq(:locked)
    end

    it 'reads what ExtendedState and State report, as the app reads them' do
      serve({ 3 => 2, 50 => [0x00, 0x2A], 52 => [0x01, 0x90], 62 => 0b10, 65 => 1, 66 => 4 },
            'TargetTemperature' => [4000], 'SpinningSpeed' => 1400)
      expect(washer.readings).to eq(described_class::Reading.new(load: 2, soiling: 4, drying_level: 0, washing: true,
                                                                 drying: false, eco: true, energy: 42, water: 400,
                                                                 temperature: 40, spin_speed: 1400))
    end

    it 'reads a WMV96 program list from 8200' do
      washer.program_list
      expect(JSON.parse(fake.requests.last.body)).to eq('Request' => '82000100')
    end
  end
end
