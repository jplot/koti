# frozen_string_literal: true

RSpec.describe Miele::Sdk::CoolingAppliance do
  subject(:fridge) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { waits << seconds }) }

  let(:fab) { '000123456789' }
  let(:waits) { [] }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 201) }
  let(:resources) do
    { 'State' => { 'Status' => 5 },
      'Cooling' => { 'ZoneCounter' => 2, 'PresentationType' => 3,
                     'EcoMode' => { 'Value' => 2, 'SetValues' => [1, 2] },
                     'Party' => { 'Value' => 2, 'SetValues' => [] },
                     'DoorAlarmTime' => { 'Value' => 120, 'Min' => 60, 'Max' => 300, 'Step' => 60 },
                     'Humidifier' => { 'Value' => 0, 'Min' => 0, 'Max' => 2, 'Step' => 1 },
                     'PerfectFresh' => { 'Value' => 1, 'Min' => 0, 'Max' => 2, 'Step' => 1 },
                     'IceMaker' => { 'Value' => 1 } },
      'Cooling/1' => { 'ZoneState' => { 'Value' => 1, 'Type' => 20, 'Position' => 3 }, 'Fan' => { 'Value' => 2 },
                       'SuperMode' => { 'Value' => 2, 'SetValues' => [1, 2] }, 'VarioCool' => { 'Value' => 2 },
                       'TargetTemp' => { 'Value' => -1800, 'Min' => -2400, 'Max' => -1400, 'Step' => 200 } },
      'Cooling/2' => { 'ZoneState' => { 'Value' => 1, 'Type' => 19, 'Position' => 1 } } }
  end
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      path = request.path.delete_prefix("/Devices/#{fab}/")
      case request
      in { path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET' } then [200, {}, JSON.generate(served.fetch(path))]
      else served.fetch(path) { [204, {}, ''] }
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def written
    fake.requests.reject { it.verb == 'GET' }.map do |request|
      [request.verb, request.path.delete_prefix("/Devices/#{fab}/"), JSON.parse(request.body)]
    end
  end

  def freezer = fridge.zones.find { it.number == 1 }

  it 'sets a zone target in hundredths of a degree, on its number' do
    fridge.set_target(freezer, -20)
    expect(written).to eq([['PUT', 'Cooling/1/TargetTemp', { 'Value' => -2000 }]])
  end

  it "sends nothing for the zone's current target, as the app does" do
    fridge.set_target(freezer, -18)
    expect(written).to be_empty
  end

  it "refuses a target off the zone's Min to Max by Step, as the app's picker", :aggregate_failures do
    expect { fridge.set_target(freezer, -17) }.to raise_error(ArgumentError)
    expect { fridge.set_target(freezer, -26) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'offers the values the zone lists, else its target rounded half away from zero', :aggregate_failures do
    resources['Cooling/1']['TargetTemp'] = { 'Value' => -1850, 'AllValues' => [-2000, -1800] }
    expect { fridge.set_target(freezer, -19) }.to raise_error(ArgumentError)
    resources['Cooling/1']['TargetTemp'] = { 'Value' => -1850, 'Min' => -1400, 'Max' => -2400, 'Step' => 100 }
    fridge.set_target(freezer, -19)
    expect(written).to eq([['PUT', 'Cooling/1/TargetTemp', { 'Value' => -1900 }]])
  end

  it 'sets the super mode duration first on protocol 201, then waits half a second', :aggregate_failures do
    fridge.set_super_mode(freezer, true)
    expect(written).to eq([['PUT', 'Cooling/1/SuperModeDuration', { 'Value' => 720 }],
                           ['PUT', 'Cooling/1/SuperMode', { 'Value' => 1, 'SetValues' => [1, 2] }]])
    expect(waits).to eq([0.5])
  end

  it 'sets the super mode even when the duration write fails, as the app does' do
    resources['Cooling/1/SuperModeDuration'] = [500, {}, '']
    fridge.set_super_mode(freezer, false)
    expect(written.last).to eq(['PUT', 'Cooling/1/SuperMode', { 'Value' => 2, 'SetValues' => [1, 2] }])
  end

  it 'switches the fan on the zone position and VarioCool on its rank' do
    fridge.set_fan(freezer, true)
    fridge.set_vario_cool(freezer, true)
    expect(written).to eq([['PUT', 'Cooling/3/Fan', { 'Value' => 1, 'SetValues' => [1, 2] }],
                           ['PUT', 'Cooling/2/VarioCool', { 'Value' => 1 }]])
  end

  it 'refuses a fan or VarioCool on a zone without one', :aggregate_failures do
    fridge_zone = fridge.zones.find { it.number == 2 }
    expect { fridge.set_fan(fridge_zone, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.set_vario_cool(fridge_zone, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'refuses zone controls but the super mode in Holiday mode while on, as the app hides the zones',
     :aggregate_failures do
    resources['State'] = { 'Status' => 2 }
    resources['Cooling']['Holiday'] = { 'Value' => 1 }
    expect { fridge.set_target(freezer, -18) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.set_fan(freezer, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.set_vario_cool(freezer, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    fridge.set_super_mode(freezer, true)
    expect(written.last).to eq(['PUT', 'Cooling/1/SuperMode', { 'Value' => 1, 'SetValues' => [1, 2] }])
  end

  it 'shows the zones in Holiday mode under an ice maker or a freezer temperature alarm, as the app does' do
    resources['Cooling'].merge!('Holiday' => { 'Value' => 1 }, 'IceMaker' => { 'Value' => 3 })
    fridge.set_fan(freezer, true)
    resources['Cooling']['IceMaker'] = { 'Value' => 1 }
    resources['Cooling/1']['TempAlarm'] = { 'Value' => 3 }
    fridge.set_fan(freezer, false)
    expect(written.size).to eq(2)
  end

  it 'hides the zones in Holiday mode despite a temperature alarm in a fridge zone, as the app does' do
    resources['Cooling']['Holiday'] = { 'Value' => 1 }
    resources['Cooling/2']['TempAlarm'] = { 'Value' => 3 }
    expect { fridge.set_fan(freezer, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'shows the zones in a failure only with a door alarm or a failure alarm, as the app does', :aggregate_failures do
    resources['State'] = { 'Status' => 8, 'SignalDoor' => true, 'SignalFailure' => false }
    expect { fridge.set_fan(freezer, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    resources['State'] = { 'Status' => 8, 'SignalDoor' => true, 'SignalFailure' => true }
    fridge.set_fan(freezer, true)
    resources.merge!('State' => { 'Status' => 8 }, 'Cooling/2' => { 'PowerFailAlarm' => { 'Value' => 3 } })
    fridge.set_fan(freezer, false)
    expect(written.size).to eq(2)
  end

  it 'shows the zones in a failure in Sabbath mode, as the app does' do
    resources['State'] = { 'Status' => 8 }
    resources['Cooling']['Sabbath'] = { 'Value' => 1 }
    fridge.set_fan(freezer, true)
    expect(written.size).to eq(1)
  end

  it 'checks the zones against a single read of State' do
    zone = freezer
    reads = -> { fake.requests.count { it.verb == 'GET' && it.path.end_with?('/State') } }
    expect { fridge.set_fan(zone, true) }.to change(reads, :call).by(1)
  end

  it 'refuses every zone control while off with Status 10, which the app reads as off', :aggregate_failures do
    resources['State'] = { 'Status' => 10 }
    expect { fridge.set_target(freezer, -18) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.set_super_mode(freezer, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'shows the zones in Sabbath mode while super cooling or with the door open, as the app does' do
    resources['Cooling']['Sabbath'] = { 'Value' => 1 }
    resources['State'] = { 'Status' => 14 }
    fridge.set_target(freezer, -16)
    resources['State'] = { 'Status' => 5, 'SignalDoor' => true, 'SignalFailure' => false }
    fridge.set_target(freezer, -20)
    expect(written.map(&:last)).to eq([{ 'Value' => -1600 }, { 'Value' => -2000 }])
  end

  it 'sets a mode by its name in the Cooling API, only when the appliance lists values for it', :aggregate_failures do
    fridge.set_mode(:eco, true)
    expect { fridge.set_mode(:party, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.set_mode(:holiday, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to eq([['PUT', 'Cooling/EcoMode', { 'Value' => 1 }]])
  end

  it 'sets the ice maker, the door alarm delay and the humidifier' do
    fridge.ice_maker = false
    fridge.door_alarm_delay = 180
    fridge.humidifier = 1
    expect(written.map { it[1..] }).to eq([['Cooling/IceMaker', { 'Value' => 2 }],
                                           ['Cooling/DoorAlarmTime', { 'Value' => 180 }],
                                           ['Cooling/Humidifier', { 'Value' => 1 }]])
  end

  it "refuses a door alarm delay or a humidifier off the appliance's Min to Max by Step", :aggregate_failures do
    expect { fridge.door_alarm_delay = 90 }.to raise_error(ArgumentError)
    expect { fridge.door_alarm_delay = 360 }.to raise_error(ArgumentError)
    expect { fridge.humidifier = -1 }.to raise_error(ArgumentError)
    expect { fridge.humidifier = 3 }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'refuses the humidifier or the door alarm delay at a Value of -1 or absent, as the app hides their cells',
     :aggregate_failures do
    resources['Cooling'].merge!('Humidifier' => { 'Value' => -1, 'Min' => -1, 'Max' => -1, 'Step' => 1 })
    resources['Cooling'].delete('DoorAlarmTime')
    expect { fridge.humidifier = -1 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.door_alarm_delay = 60 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'refuses the ice maker without a state, as the app hides its switch', :aggregate_failures do
    resources['Cooling']['IceMaker'] = { 'Value' => 0 }
    expect { fridge.ice_maker = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
    resources['Cooling'].delete('IceMaker')
    expect { fridge.ice_maker = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'refuses PerfectFresh on protocol 201, where the app reads none', :aggregate_failures do
    expect { fridge.perfect_fresh = 1 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'refuses a light, an ambient light or a humidity level on a fridge-freezer', :aggregate_failures do
    expect { fridge.light = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.ambient_light_mode = 2 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { fridge.humidity = :high }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  context 'with four wine zones in Sabbath mode' do
    before do
      resources['Cooling'].merge!('ZoneCounter' => 4, 'Sabbath' => { 'Value' => 1 })
      (1..4).each do |number|
        resources["Cooling/#{number}"] = { 'ZoneState' => { 'Value' => 1, 'Type' => 32, 'Position' => number },
                                           'Fan' => {} }
      end
    end

    it 'counts a temperature alarm in a wine unit zone, which the third is not when the fourth is wine',
       :aggregate_failures do
      resources['Cooling/3']['TempAlarm'] = { 'Value' => 3 }
      expect { fridge.set_fan(fridge.zones.first, true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      resources['Cooling/2']['TempAlarm'] = { 'Value' => 3 }
      fridge.set_fan(fridge.zones.first, true)
      expect(written.size).to eq(1)
    end
  end

  context 'with a BSH fridge-freezer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 200) }

    it "sets PerfectFresh only to the appliance's Min to Max by Step", :aggregate_failures do
      expect { fridge.perfect_fresh = 3 }.to raise_error(ArgumentError)
      fridge.perfect_fresh = 2
      expect(written).to eq([['PUT', 'Cooling/PerfectFresh', { 'Value' => 2 }]])
    end

    it 'refuses PerfectFresh without a Step, as the app hides it' do
      resources['Cooling']['PerfectFresh'] = { 'Value' => 1, 'Min' => 0, 'Max' => 2, 'Step' => 0 }
      expect { fridge.perfect_fresh = 1 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with a fridge, which has no ice maker' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 19, 'ProtocolVersion' => 201) }

    it 'refuses the ice maker' do
      expect { fridge.ice_maker = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with a Liebherr KWTUS wine unit on protocol 203' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 34, 'ProtocolVersion' => 203,
                                                    'DeviceIdentLabel' => { 'TechType' => 'KWTUS 6000' })
    end

    before { resources['Cooling']['HumidityControl'] = { 'Value' => 2, 'Min' => 1, 'Max' => 3, 'Step' => 1 } }

    it 'lights it through State, and sets its humidity level' do
      fridge.light = true
      fridge.humidity = :high
      expect(written).to eq([['PUT', 'State/Light', { 'Light' => 1 }],
                             ['PUT', 'Cooling/HumidityControl', { 'Value' => 3 }]])
    end

    it 'refuses a humidity level in Sabbath mode, in a failure or at a Value of -1, as the app hides it',
       :aggregate_failures do
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect { fridge.humidity = :high }.to raise_error(Miele::Sdk::ActionUnavailableError)
      resources.merge!('State' => { 'Status' => 8 }, 'Cooling' => { 'HumidityControl' => { 'Value' => 2 } })
      expect { fridge.humidity = :high }.to raise_error(Miele::Sdk::ActionUnavailableError)
      resources.merge!('State' => { 'Status' => 5 }, 'Cooling' => { 'HumidityControl' => { 'Value' => -1 } })
      expect { fridge.humidity = :high }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end

    it 'refuses a humidity level off its Min to Max by Step, as the app offers none' do
      resources['Cooling']['HumidityControl'] = { 'Value' => 2, 'Min' => 1, 'Max' => 2, 'Step' => 1 }
      expect { fridge.humidity = :high }.to raise_error(ArgumentError)
    end
  end

  context 'with a Liebherr wine unit on protocol 203' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 203,
                                                    'DeviceIdentLabel' => { 'TechType' => 'WT 6000' })
    end

    it 'sets its ambient light level on Cooling/Light' do
      fridge.ambient_light_mode = 4
      expect(written).to eq([['PUT', 'Cooling/Light', { 'Value' => 4 }]])
    end
  end

  context 'with a BSH wine unit' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 200) }

    it 'lights it through AmbientLightState and sets its ambient light mode' do
      fridge.light = false
      fridge.ambient_light_mode = 2
      expect(written).to eq([['PUT', 'Cooling/AmbientLightState', { 'Value' => 2, 'SetValues' => [1, 2] }],
                             ['PUT', 'Cooling/AmbientLightMode', { 'Value' => 2 }]])
    end
  end

  context 'with a Rioja wine unit, which has a presentation light' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 203,
                                                    'DeviceIdentLabel' => { 'TechType' => 'KWT 4154 UG' })
    end

    before { resources['Cooling']['PresentationLight'] = { 'Value' => 2 } }

    it 'switches the presentation light and sets a zone intensity on its rank' do
      fridge.presentation_light = true
      fridge.set_presentation_light_intensity(freezer, 0)
      expect(written).to eq([['PUT', 'Cooling/PresentationLight', { 'Value' => 1 }],
                             ['PUT', 'Cooling/2/PresentationLightIntensity', { 'Value' => 0 }]])
    end

    it 'sets a zone intensity with Status 10, where the app still shows its presenter light' do
      resources['State'] = { 'Status' => 10 }
      fridge.set_presentation_light_intensity(freezer, 0)
      expect(written.size).to eq(1)
    end

    it 'refuses a zone intensity in Sabbath mode, even super cooling, as the app hides its presenter light' do
      resources['State'] = { 'Status' => 14 }
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect { fridge.set_presentation_light_intensity(freezer, 0) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end

    it 'refuses the presentation light without a light state, as the app shows none', :aggregate_failures do
      resources['Cooling']['PresentationLight'] = { 'Value' => 0 }
      expect { fridge.presentation_light = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { fridge.set_presentation_light_intensity(freezer, 0) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end

    it "switches the light where only the dashboard's quick action shows it, never its intensity",
       :aggregate_failures do
      resources['State'] = { 'Status' => 8 }
      fridge.presentation_light = true
      expect { fridge.set_presentation_light_intensity(freezer, 0) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      resources['State'] = { 'Status' => 5 }
      resources['Cooling'].merge!('Sabbath' => { 'Value' => 1 }, 'DustFilter' => { 'Value' => 3 })
      fridge.presentation_light = false
      expect(written.map { it[1] }).to eq(%w[Cooling/PresentationLight Cooling/PresentationLight])
    end

    it 'refuses the light in Sabbath mode with no notice ranked before it, as the app hides it everywhere' do
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect { fridge.presentation_light = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with an Opcode fridge-freezer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 1) }

    before do
      resources['State'] = { 'Status' => 5, 'Temperature' => [500, -1800], 'TargetTemperature' => [400, -1800] }
    end

    it "sets a target through Oc85 in whole °C, as 16-bit two's complement" do
      fridge.set_target(fridge.zones.last, -20)
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '10000617000200FFEC' }]])
    end

    it 'sends nothing for the current target, as the app does' do
      fridge.set_target(fridge.zones.last, -18)
      expect(written).to be_empty
    end

    it 'switches super freezing with ProcessAction 4' do
      fridge.set_super_mode(fridge.zones.last, true)
      expect(written).to eq([['PUT', 'State/ProcessAction', { 'ProcessAction' => 4 }]])
    end

    it 'refuses a target outside the range the app fixes for each zone', :aggregate_failures do
      expect { fridge.set_target(fridge.zones.first, 1) }.to raise_error(ArgumentError)
      expect { fridge.set_target(fridge.zones.last, -13) }.to raise_error(ArgumentError)
      fridge.set_target(fridge.zones.first, 2)
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '100006170001000002' }]])
    end

    context 'with a KFN 37692 iDE' do
      let(:ident) do
        Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 1,
                                                      'DeviceIdentLabel' => { 'TechType' => 'KFN 37692 iDE' })
      end

      it 'keeps its fridge to 3 to 9 °C and its freezer to -26 to -15 °C', :aggregate_failures do
        expect { fridge.set_target(fridge.zones.first, 2) }.to raise_error(ArgumentError)
        expect { fridge.set_target(fridge.zones.last, -14) }.to raise_error(ArgumentError)
        fridge.set_target(fridge.zones.first, 9)
        expect(written).to eq([['POST', 'Oc85/', { 'Request' => '100006170001000009' }]])
      end
    end

    context 'with an FN 30402 i freezer' do
      let(:ident) do
        Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 20, 'ProtocolVersion' => 1,
                                                      'DeviceIdentLabel' => { 'TechType' => 'FN 30402 i' })
      end

      it 'keeps it to -28 to -15 °C' do
        expect { fridge.set_target(fridge.zones.first, -14) }.to raise_error(ArgumentError)
      end
    end

    context 'with a wine unit of four zones' do
      let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 1) }

      before do
        resources['State'] = { 'Status' => 5, 'Temperature' => [1200, 1400, 1600, 1800],
                               'TargetTemperature' => [1200, 1450, 1600, 1800] }
      end

      it 'offers 5 to 20 °C in its first zone and only the current target in the others, as the app',
         :aggregate_failures do
        first, second = fridge.zones
        expect { fridge.set_target(second, 14) }.to raise_error(ArgumentError)
        fridge.set_target(second, 15)
        fridge.set_target(first, 20)
        expect(written.map { it[2]['Request'] }).to eq(%w[10000617000200000F 100006170001000014])
      end
    end
  end
end
