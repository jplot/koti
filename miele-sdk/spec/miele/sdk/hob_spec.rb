# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hob do
  subject(:hob) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:protocol) { 2 }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 27, 'ProtocolVersion' => protocol) }
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def serve(bytes, size = 62, state = {})
    data = Array.new(size, 0)
    bytes.each { |index, value| Array(value).each_with_index { |byte, offset| data[index + offset] = byte } }
    resources['State'] = JSON.generate({ 'Status' => 5, 'ExtendedState' => data.pack('C*').unpack1('H*') }.merge(state))
  end

  def zone(number, **values)
    described_class::Zone.new(number:, level: 0.0, heat: nil, booster: 0, timer: nil, cookware: false, bridged: false,
                              temp_control: false, secondary: false).with(**values)
  end

  it 'reads each zone from ExtendedState as the app does' do
    serve(7 => 3 << 1, 8 => 6, 9 => 0b1000_1000, 28 => [30, 1], 11 => 101, 13 => 0b0011_0000)
    expect(hob.zones).to eq([zone(1, level: 6.0, booster: 2, timer: 5400, cookware: true),
                             zone(2, level: nil, heat: :residual1, bridged: true, temp_control: true), zone(3)])
  end

  it 'reads no timer where the end time only gives its kind, as the app does' do
    serve(7 => 1 << 1, 28 => [0xC0, 0x00])
    expect(hob.zones.first.timer).to be_nil
  end

  it 'shares a timer between two bridged zones, but not on a 159-byte hob, as the app does', :aggregate_failures do
    bridged = { 7 => 2 << 1, 10 => 0b1_0000, 13 => 0b1_0000, 28 => [30, 1] }
    serve(bridged)
    expect(hob.zones.map(&:timer)).to eq([5400, 5400])
    serve(bridged, 137)
    expect(hob.zones.map(&:timer)).to eq([5400, nil])
  end

  it 'marks the zone of a bridged pair the app hides: the one not boosted, else the second', :aggregate_failures do
    bridged = { 7 => 2 << 1, 10 => 0b1_0000, 13 => 0b1_0000 }
    serve(bridged)
    expect(hob.zones.map(&:secondary)).to eq([false, true])
    serve(bridged.merge(12 => 0b0100_0000))
    expect(hob.zones.map(&:secondary)).to eq([true, false])
  end

  it 'reads half steps when the hob doubles its levels' do
    serve(6 => 0b1_0000, 7 => 1 << 1, 8 => 4)
    expect(hob.zones.map(&:level)).to eq([2.5])
  end

  it 'counts only the zones the hob declares, and shows zone 5 fourth while it heats' do
    serve(7 => 4 << 1, 20 => 3)
    expect(hob.zones.map(&:number)).to eq([1, 2, 3, 5])
  end

  it 'reads no fan where the byte says none', :aggregate_failures do
    serve({ 62 => 0xFF }, 66)
    expect(hob.fan).to be_nil
    serve({ 62 => 2, 64 => 5, 65 => 1 }, 66)
    expect(hob.fan).to eq(described_class::Fan.new(level: 2, run_on: 301))
  end

  it 'reads a fan only on the hobs the app gives one, of 88, 128 or 159 bytes', :aggregate_failures do
    serve({ 62 => 2, 64 => 5, 65 => 1 }, 78)
    expect(hob.fan).to be_nil
    serve({}, 58)
    expect(hob.fan).to be_nil
    serve({ 62 => 2, 64 => 5, 65 => 1 }, 106)
    expect(hob.fan).to eq(described_class::Fan.new(level: 2, run_on: 301))
  end

  it 'reads the minute minder, power doubling and Stop&Go', :aggregate_failures do
    serve(0 => 13, 1 => 10, 2 => 2, 6 => 0b0100)
    expect([hob.minute_minder, hob.power_doubling?, hob.stop_and_go?]).to eq([130, false, true])
    expect(hob.main_state).to eq(:off)
  end

  it 'reads TempControl for the zone that has it' do
    temperatures = { 'TargetTemperature' => [12_000], 'Temperature' => [9_500] }
    serve({ 7 => 2 << 1, 13 => 0b0010_0000, 57 => 0b0001_1000 }, 62, temperatures)
    expect(hob.temp_control).to eq(described_class::TempControl.new(zone: 2, level: :two, target_reached: true,
                                                                    target: 120, current: 95))
  end

  it 'reads TempControl in whole degrees, 0 where there is none, as the app does' do
    temperatures = { 'TargetTemperature' => [12_050], 'Temperature' => [-32_768] }
    serve({ 7 => 2 << 1, 13 => 0b0010_0000, 57 => 0b0001_1000 }, 62, temperatures)
    expect(hob.temp_control).to have_attributes(target: 120, current: 0)
  end

  it 'numbers the zones of a FlexControl hob from their controls' do
    serve({ 7 => 2 << 1, 8 => 1, 11 => 2, 68 => 3 }, 137)
    expect(hob.zones.map { [it.number, it.level] }).to eq([[1, 2.0], [3, 1.0]])
  end

  it 'reads the internal state the app names' do
    serve({}, 62, { 'InternalState' => 146 })
    expect(hob.internal_state).to eq(:stop_and_go)
  end

  it 'reads no zone when ExtendedState is empty, as a hob switched off', :aggregate_failures do
    resources['State'] = JSON.generate('Status' => 1, 'ExtendedState' => '')
    expect([hob.zones, hob.main_state, hob.fan, hob.minute_minder]).to eq([[], :off, nil, nil])
  end

  context 'with a DOP2 hob' do
    let(:protocol) { 4 }

    it 'reads zones 1 and 2 from 2/256, as the app does', :aggregate_failures do
      extended = { 9 => dop2_field(:u8, 4), 12 => dop2_field(:u8, 0), 28 => dop2_field(:u16, (30 << 8) | 1) }
      resources['DOP2/2/256'] = dop2_leaf(2, 256, { 1 => dop2_field(:e8, 5), 31 => dop2_field(:struct, extended) })
      expect(hob.zones).to eq([zone(1, level: 2.5, timer: 5400), zone(2)])
      expect(hob.main_state).to eq(:running)
    end
  end
end
