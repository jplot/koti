# frozen_string_literal: true

RSpec.describe Miele::Sdk::CoolingAppliance do
  subject(:fridge) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 201) }
  let(:resources) do
    { 'State' => { 'Status' => 5 },
      'Cooling' => { 'ZoneCounter' => 2, 'PresentationType' => 3, 'TempUnit' => { 'Value' => 1 },
                     'EcoMode' => { 'Value' => 2, 'SetValues' => [1, 2] },
                     'Party' => { 'Value' => 1, 'SetValues' => [] }, 'DustFilter' => { 'Value' => 3 },
                     'WaterFilter' => { 'Value' => 2 }, 'DemoMode' => { 'Value' => 1 },
                     'DoorAlarmTime' => { 'Value' => 120, 'Min' => 60, 'Max' => 300, 'Step' => 60 },
                     'PerfectFresh' => { 'Value' => 2 }, 'HumidityControl' => { 'Value' => 2 },
                     'AmbientLightState' => { 'Value' => 1 } },
      'Cooling/1' => { 'Temp' => { 'Value' => 500 }, 'ZoneState' => { 'Value' => 1, 'Type' => 19, 'Position' => 1 },
                       'TargetTemp' => { 'Value' => 400 }, 'SuperMode' => { 'Value' => 2, 'SetValues' => [1, 2] },
                       'Fan' => { 'Value' => 1 } },
      'Cooling/2' => { 'Temp' => { 'Value' => -1800 }, 'ZoneState' => { 'Value' => 1, 'Type' => 20, 'Position' => 3 },
                       'TargetTemp' => { 'Value' => -1800 }, 'SuperMode' => { 'Value' => 1, 'SetValues' => [1, 2] },
                       'VarioCool' => { 'Value' => 2 } } }
  end
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request.path
      when '/Devices/' then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      else [200, {}, JSON.generate(served.fetch(request.path.delete_prefix("/Devices/#{fab}/")))]
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def zone(**given)
    described_class::Zone.new(fan: nil, vario_cool: nil, super_mode: nil, **given)
  end

  it 'reads each zone of the Cooling API in hundredths of a degree, ranked by position' do
    expect(fridge.zones).to eq([zone(number: 1, position: 1, rank: 1, type: :fridge, enabled: true, temperature: 5.0,
                                     target: 4.0, super_mode: false, fan: true),
                                zone(number: 2, position: 3, rank: 2, type: :freezer, enabled: true,
                                     temperature: -18.0, target: -18.0, super_mode: true, vario_cool: false)])
  end

  it 'reads the modes, editable when they list values, and the filter and demo alarms', :aggregate_failures do
    expect(fridge.modes).to eq(eco: described_class::Mode.new(on: false, editable: true),
                               party: described_class::Mode.new(on: true, editable: false))
    expect(fridge.alarms).to eq(%i[dust_filter demo_mode])
    expect(fridge.door_alarm_delay).to eq(120)
  end

  it 'reads no PerfectFresh on protocol 201, as the app does' do
    expect(fridge.perfect_fresh).to be_nil
  end

  context 'with a Liebherr wine unit on protocol 203' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 34, 'ProtocolVersion' => 203,
                                                    'DeviceIdentLabel' => { 'TechType' => 'KWTUS 6000' })
    end

    before { resources['State'] = { 'Status' => 5, 'Light' => 2 } }

    it 'reads its light from State, PerfectFresh and the humidity level', :aggregate_failures do
      expect(fridge.light).to eq(:off)
      expect(fridge.perfect_fresh).to eq(2)
      expect(fridge.humidity).to eq(:medium)
    end
  end

  context 'with a BSH wine unit' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 200) }

    it 'reads its light from AmbientLightState, and no humidity level', :aggregate_failures do
      expect(fridge.light).to eq(:on)
      expect(fridge.humidity).to be_nil
    end
  end

  it 'reads no light on a fridge, as the app does' do
    expect(fridge.light).to be_nil
  end

  context 'when the appliance is off' do
    before { resources['State'] = { 'Status' => 1 } }

    it 'reads no zone, as the app does', :aggregate_failures do
      expect(fridge.zones).to be_empty
      expect(fake.requests.map(&:path).grep(/Cooling/)).to be_empty
    end
  end

  context 'with protocol 200, a BSH appliance' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 200) }

    it 'shows no zone temperature, as the app does' do
      expect(fridge.zones.map(&:temperature)).to eq([nil, nil])
    end
  end

  context 'with an Opcode fridge-freezer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 1) }

    before do
      resources['State'] = { 'Status' => 14, 'Temperature' => [500, -1800, -32_768],
                             'TargetTemperature' => [400, -1800, -32_768] }
    end

    it 'reads its zones from State, super cooling from Status 14' do
      expect(fridge.zones).to eq([zone(number: 1, position: 1, rank: 1, type: :fridge, enabled: true,
                                       temperature: 5.0, target: 4.0, super_mode: true),
                                  zone(number: 2, position: 2, rank: 2, type: :freezer, enabled: true,
                                       temperature: -18.0, target: -18.0, super_mode: false)])
    end
  end
end
