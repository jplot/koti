# frozen_string_literal: true

RSpec.describe Miele::Sdk::CoolingAppliance do
  subject(:fridge) do
    described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { waits << seconds }, clock: -> { waits.sum })
  end

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
      in { verb: 'PUT' | 'POST' } if (refusal = served.fetch(:refusals, []).shift) then refusal
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

  it "sets a target off the zone's Min to Max by Step, or a fraction, which the app's picker does not offer",
     :aggregate_failures do
    expect(fridge.target_choices(freezer)).to eq([-24, -22, -20, -18, -16, -14])
    fridge.set_target(freezer, -17)
    fridge.set_target(freezer, -18.5)
    expect(written.map(&:last)).to eq([{ 'Value' => -1700 }, { 'Value' => -1850 }])
  end

  it 'offers the values the zone lists, else its target rounded half away from zero', :aggregate_failures do
    resources['Cooling/1']['TargetTemp'] = { 'Value' => -1850, 'AllValues' => [-2000, -1800] }
    expect(fridge.target_choices(freezer)).to eq([-20, -18])
    resources['Cooling/1']['TargetTemp'] = { 'Value' => -1850, 'Min' => -1400, 'Max' => -2400, 'Step' => 100 }
    expect(fridge.target_choices(freezer)).to eq([-19])
    fridge.set_target(freezer, -19)
    expect(written).to eq([['PUT', 'Cooling/1/TargetTemp', { 'Value' => -1900 }]])
  end

  it 'sets the super mode duration first on protocol 201, then waits half a second', :aggregate_failures do
    expect(fridge.super_mode_offered?(freezer)).to be(true)
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

  it 'switches the fan on the zone position and VarioCool on its rank', :aggregate_failures do
    expect(fridge.zones_shown?).to be(true)
    fridge.set_fan(freezer, true)
    fridge.set_vario_cool(freezer, true)
    expect(written).to eq([['PUT', 'Cooling/3/Fan', { 'Value' => 1, 'SetValues' => [1, 2] }],
                           ['PUT', 'Cooling/2/VarioCool', { 'Value' => 1 }]])
  end

  it 'switches a fan or VarioCool on a zone without one', :aggregate_failures do
    fridge_zone = fridge.zones.find { it.number == 2 }
    expect([fridge_zone.fan, fridge_zone.vario_cool]).to eq([nil, nil])
    fridge.set_fan(fridge_zone, true)
    fridge.set_vario_cool(fridge_zone, true)
    expect(written.size).to eq(2)
  end

  it 'sends zone controls in Holiday mode while on, while the app hides the zones but its super mode',
     :aggregate_failures do
    resources['State'] = { 'Status' => 2 }
    resources['Cooling']['Holiday'] = { 'Value' => 1 }
    expect([fridge.zones_shown?, fridge.super_mode_offered?(freezer)]).to eq([false, true])
    fridge.set_target(freezer, -20)
    fridge.set_fan(freezer, true)
    fridge.set_vario_cool(freezer, true)
    expect(written.size).to eq(3)
  end

  it 'shows the zones in Holiday mode under an ice maker or a freezer temperature alarm, as the app does',
     :aggregate_failures do
    resources['Cooling'].merge!('Holiday' => { 'Value' => 1 }, 'IceMaker' => { 'Value' => 3 })
    expect(fridge.zones_shown?).to be(true)
    resources['Cooling']['IceMaker'] = { 'Value' => 1 }
    resources['Cooling/1']['TempAlarm'] = { 'Value' => 3 }
    expect(fridge.zones_shown?).to be(true)
  end

  it 'hides the zones in Holiday mode despite a temperature alarm in a fridge zone, as the app does' do
    resources['Cooling']['Holiday'] = { 'Value' => 1 }
    resources['Cooling/2']['TempAlarm'] = { 'Value' => 3 }
    expect(fridge.zones_shown?).to be(false)
  end

  it 'shows the zones in a failure only with a door alarm or a failure alarm, as the app does', :aggregate_failures do
    resources['State'] = { 'Status' => 8, 'SignalDoor' => true, 'SignalFailure' => false }
    expect(fridge.zones_shown?).to be(false)
    resources['State'] = { 'Status' => 8, 'SignalDoor' => true, 'SignalFailure' => true }
    expect(fridge.zones_shown?).to be(true)
    resources.merge!('State' => { 'Status' => 8 }, 'Cooling/2' => { 'PowerFailAlarm' => { 'Value' => 3 } })
    expect(fridge.zones_shown?).to be(true)
  end

  it 'shows the zones in a failure in Sabbath mode, as the app does' do
    resources['State'] = { 'Status' => 8 }
    resources['Cooling']['Sabbath'] = { 'Value' => 1 }
    expect(fridge.zones_shown?).to be(true)
  end

  it 'reads State once to tell whether the app shows the zones' do
    reads = -> { fake.requests.count { it.verb == 'GET' && it.path.end_with?('/State') } }
    expect { fridge.zones_shown? }.to change(reads, :call).by(1)
  end

  it 'sends every zone control while off with Status 10, which the app reads as off', :aggregate_failures do
    resources['State'] = { 'Status' => 10 }
    expect([fridge.zones_shown?, fridge.super_mode_offered?(freezer)]).to eq([false, false])
    fridge.set_target(freezer, -20)
    fridge.set_super_mode(freezer, true)
    expect(written.map { it[1] }).to eq(%w[Cooling/1/TargetTemp Cooling/1/SuperModeDuration Cooling/1/SuperMode])
  end

  it 'shows the zones in Sabbath mode while super cooling or with the door open, as the app does',
     :aggregate_failures do
    resources['Cooling']['Sabbath'] = { 'Value' => 1 }
    resources['State'] = { 'Status' => 14 }
    expect(fridge.zones_shown?).to be(true)
    resources['State'] = { 'Status' => 5, 'SignalDoor' => true, 'SignalFailure' => false }
    expect(fridge.zones_shown?).to be(true)
  end

  it 'sets a mode by its name in the Cooling API, one the appliance lists no values for too', :aggregate_failures do
    expect(fridge.modes.transform_values(&:editable)).to eq(eco: true, party: false)
    fridge.set_mode(:eco, true)
    fridge.set_mode(:party, true)
    fridge.set_mode(:holiday, true)
    expect(written.map { it[1] }).to eq(%w[Cooling/EcoMode Cooling/Party Cooling/Holiday])
  end

  it 'sets a mode once despite a 5xx, the 5 s Timeout leaving no room for the 5 s retry', :aggregate_failures do
    resources[:refusals] = [[500, {}, '']]
    expect { fridge.set_mode(:eco, true) }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
    expect([written.size, waits]).to eq([1, []])
  end

  it 'sets the ice maker, the door alarm delay and the humidifier', :aggregate_failures do
    expect(%i[ice_maker_offered? door_alarm_delay_offered? humidifier_offered?].map { fridge.public_send(it) })
      .to eq([true, true, true])
    fridge.ice_maker = false
    fridge.door_alarm_delay = 180
    fridge.humidifier = 1
    expect(written.map { it[1..] }).to eq([['Cooling/IceMaker', { 'Value' => 2 }],
                                           ['Cooling/DoorAlarmTime', { 'Value' => 180 }],
                                           ['Cooling/Humidifier', { 'Value' => 1 }]])
  end

  it "sets a door alarm delay or a humidifier off the appliance's Min to Max by Step, off the app's pickers",
     :aggregate_failures do
    expect([fridge.door_alarm_delay_choices, fridge.humidifier_choices]).to eq([[60, 120, 180, 240, 300], [0, 1, 2]])
    fridge.door_alarm_delay = 90
    fridge.humidifier = 3
    expect(written.map(&:last)).to eq([{ 'Value' => 90 }, { 'Value' => 3 }])
  end

  it 'sets the humidifier or the door alarm delay at a Value of -1 or absent, while the app hides their cells',
     :aggregate_failures do
    resources['Cooling'].merge!('Humidifier' => { 'Value' => -1, 'Min' => -1, 'Max' => -1, 'Step' => 1 })
    resources['Cooling'].delete('DoorAlarmTime')
    expect([fridge.humidifier_offered?, fridge.door_alarm_delay_offered?]).to eq([false, false])
    fridge.humidifier = -1
    fridge.door_alarm_delay = 60
    expect(written.size).to eq(2)
  end

  it 'switches the ice maker without a state, while the app hides its switch', :aggregate_failures do
    resources['Cooling']['IceMaker'] = { 'Value' => 0 }
    expect(fridge.ice_maker_offered?).to be(false)
    resources['Cooling'].delete('IceMaker')
    expect(fridge.ice_maker_offered?).to be(false)
    fridge.ice_maker = true
    expect(written).to eq([['PUT', 'Cooling/IceMaker', { 'Value' => 1 }]])
  end

  it 'switches an ice maker in alarm, whose switch the app still shows', :aggregate_failures do
    resources['Cooling']['IceMaker'] = { 'Value' => 3 }
    expect(fridge.ice_maker_offered?).to be(true)
    fridge.ice_maker = false
    expect(written).to eq([['PUT', 'Cooling/IceMaker', { 'Value' => 2 }]])
  end

  it 'tells the app hides the ice maker, humidifier and door alarm cells at Status 1 or 255', :aggregate_failures do
    [1, 255].each do |status|
      resources['State'] = { 'Status' => status }
      expect(%i[ice_maker_offered? humidifier_offered? door_alarm_delay_offered?].map { fridge.public_send(it) })
        .to eq([false, false, false])
    end
  end

  it 'sets PerfectFresh on protocol 201, where the app reads none', :aggregate_failures do
    expect(fridge.perfect_fresh_offered?).to be(false)
    fridge.perfect_fresh = 1
    expect(written).to eq([['PUT', 'Cooling/PerfectFresh', { 'Value' => 1 }]])
  end

  it 'sends a light and a humidity level to a fridge-freezer, which the app offers neither', :aggregate_failures do
    expect(%i[light_offered? ambient_light_offered? humidity_offered?].map { fridge.public_send(it) })
      .to eq([false, false, false])
    fridge.light = true
    fridge.humidity = :high
    expect(written.map { it[1] }).to eq(%w[State/Light Cooling/HumidityControl])
  end

  it 'sets no ambient light on protocol 201, which has no such setting' do
    expect { fridge.ambient_light_mode = 2 }.to raise_error(Miele::Sdk::ActionUnavailableError)
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
      expect(fridge.zones_shown?).to be(false)
      resources['Cooling/2']['TempAlarm'] = { 'Value' => 3 }
      expect(fridge.zones_shown?).to be(true)
    end
  end

  context 'with a BSH fridge-freezer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 200) }

    it "sets PerfectFresh off the appliance's Min to Max by Step, which the app's picker does not offer",
       :aggregate_failures do
      expect([fridge.perfect_fresh_offered?, fridge.perfect_fresh_choices]).to eq([true, [0, 1, 2]])
      fridge.perfect_fresh = 3
      expect(written).to eq([['PUT', 'Cooling/PerfectFresh', { 'Value' => 3 }]])
    end

    it 'tells the app hides PerfectFresh at Status 1 or 255' do
      [1, 255].each do |status|
        resources['State'] = { 'Status' => status }
        expect(fridge.perfect_fresh_offered?).to be(false)
      end
    end

    it 'tells the app hides PerfectFresh without a Step, its picker offering nothing', :aggregate_failures do
      resources['Cooling']['PerfectFresh'] = { 'Value' => 1, 'Min' => 0, 'Max' => 2, 'Step' => 0 }
      expect([fridge.perfect_fresh_offered?, fridge.perfect_fresh_choices]).to eq([false, []])
    end
  end

  context 'with a fridge, which has no ice maker' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 19, 'ProtocolVersion' => 201) }

    it 'switches an ice maker, which the app does not show', :aggregate_failures do
      expect(fridge.ice_maker_offered?).to be(false)
      fridge.ice_maker = true
      expect(written.size).to eq(1)
    end
  end

  context 'with a Liebherr KWTUS wine unit on protocol 203' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 34, 'ProtocolVersion' => 203,
                                                    'DeviceIdentLabel' => { 'TechType' => 'KWTUS 6000' })
    end

    before { resources['Cooling']['HumidityControl'] = { 'Value' => 2, 'Min' => 1, 'Max' => 3, 'Step' => 1 } }

    it 'lights it through State, and sets its humidity level', :aggregate_failures do
      expect([fridge.light_offered?, fridge.humidity_offered?]).to eq([true, true])
      fridge.light = true
      fridge.humidity = :high
      expect(written).to eq([['PUT', 'State/Light', { 'Light' => 1 }],
                             ['PUT', 'Cooling/HumidityControl', { 'Value' => 3 }]])
    end

    it 'tells the app hides its humidity level in Sabbath mode, in a failure or at a Value of -1',
       :aggregate_failures do
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect(fridge.humidity_offered?).to be(false)
      resources.merge!('State' => { 'Status' => 8 }, 'Cooling' => { 'HumidityControl' => { 'Value' => 2 } })
      expect(fridge.humidity_offered?).to be(false)
      resources.merge!('State' => { 'Status' => 5 }, 'Cooling' => { 'HumidityControl' => { 'Value' => -1 } })
      expect(fridge.humidity_offered?).to be(false)
    end

    it 'tells the app sets no ambient light on a KWTUS, though its light is on and listed' do
      resources['State'] = { 'Status' => 5, 'Light' => 1 }
      resources['Cooling']['Light'] = { 'Value' => 3 }
      expect(fridge.ambient_light_offered?).to be(false)
    end

    it 'tells the app shows its humidity level in a failure with a door signal' do
      resources['State'] = { 'Status' => 8, 'SignalDoor' => true, 'SignalFailure' => false }
      expect(fridge.humidity_offered?).to be(true)
    end

    it 'sets a humidity level off its Min to Max by Step, which the app does not offer, but none it does not name',
       :aggregate_failures do
      resources['Cooling']['HumidityControl'] = { 'Value' => 2, 'Min' => 1, 'Max' => 2, 'Step' => 1 }
      expect(fridge.humidity_choices).to eq(%i[low medium])
      fridge.humidity = :high
      expect { fridge.humidity = :wet }.to raise_error(KeyError)
      expect(written).to eq([['PUT', 'Cooling/HumidityControl', { 'Value' => 3 }]])
    end
  end

  context 'with a Liebherr wine unit on protocol 203' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 203,
                                                    'DeviceIdentLabel' => { 'TechType' => 'WT 6000' })
    end

    before do
      resources['State'] = { 'Status' => 5, 'Light' => 1 }
      resources['Cooling']['Light'] = { 'Value' => 3 }
    end

    it 'sets its ambient light level on Cooling/Light', :aggregate_failures do
      expect(fridge.ambient_light_offered?).to be(true)
      fridge.ambient_light_mode = 4
      expect(written).to eq([['PUT', 'Cooling/Light', { 'Value' => 4 }]])
    end

    it "sets an ambient light level off the app's seven slider options", :aggregate_failures do
      expect(fridge.ambient_light_choices).to eq((1..7).to_a)
      fridge.ambient_light_mode = 0
      fridge.ambient_light_mode = 8
      expect(written.map(&:last)).to eq([{ 'Value' => 0 }, { 'Value' => 8 }])
    end
  end

  context 'with a BSH wine unit' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 32, 'ProtocolVersion' => 200) }

    before do
      resources['Cooling'].merge!('AmbientLightState' => { 'Value' => 1 },
                                  'AmbientLightMode' => { 'Value' => 1, 'Min' => 1, 'Max' => 4, 'Step' => 1 })
    end

    it 'switches the light without a light state, while the app shows neither its switch nor its quick action',
       :aggregate_failures do
      resources['Cooling'].delete('AmbientLightState')
      expect([fridge.light_shown?, fridge.light_offered?]).to eq([false, false])
      fridge.light = true
      expect(written.size).to eq(1)
    end

    it "tells the app switches the light in a failure through the dashboard's quick action, never off or in " \
       'Sabbath mode alone', :aggregate_failures do
      resources['State'] = { 'Status' => 8 }
      expect(fridge.light_offered?).to be(true)
      resources['State'] = { 'Status' => 10 }
      expect(fridge.light_offered?).to be(false)
      resources['State'] = { 'Status' => 5 }
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect(fridge.light_offered?).to be(false)
    end

    it 'sets the ambient light mode, which the app offers with the light on and its section shown alone',
       :aggregate_failures do
      resources['Cooling']['AmbientLightState'] = { 'Value' => 2 }
      expect(fridge.ambient_light_offered?).to be(false)
      resources['Cooling'].merge!('AmbientLightState' => { 'Value' => 1 }, 'Sabbath' => { 'Value' => 1 })
      expect(fridge.ambient_light_offered?).to be(false)
      resources['Cooling'].merge!('Sabbath' => { 'Value' => 2 }, 'AmbientLightMode' => nil)
      expect(fridge.ambient_light_offered?).to be(false)
      fridge.ambient_light_mode = 2
      expect(written).to eq([['PUT', 'Cooling/AmbientLightMode', { 'Value' => 2 }]])
    end

    it 'numbers the ambient light modes its picker lists from 1, as the app sends them', :aggregate_failures do
      resources['Cooling']['AmbientLightMode'] = { 'Value' => 1, 'Min' => 10, 'Max' => 40, 'Step' => 10 }
      expect(fridge.ambient_light_choices).to eq([1, 2, 3, 4])
      fridge.ambient_light_mode = 10
      expect(written).to eq([['PUT', 'Cooling/AmbientLightMode', { 'Value' => 10 }]])
    end

    it 'lights it through AmbientLightState and sets its ambient light mode', :aggregate_failures do
      expect([fridge.light_offered?, fridge.ambient_light_offered?]).to eq([true, true])
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

    it 'switches the presentation light and sets a zone intensity on its rank', :aggregate_failures do
      expect([fridge.presentation_light_offered?, fridge.presentation_light_intensity_offered?]).to eq([true, true])
      fridge.presentation_light = true
      fridge.set_presentation_light_intensity(freezer, 0)
      expect(written).to eq([['PUT', 'Cooling/PresentationLight', { 'Value' => 1 }],
                             ['PUT', 'Cooling/2/PresentationLightIntensity', { 'Value' => 0 }]])
    end

    it "sets a zone intensity off 0 and the app's seven slider options", :aggregate_failures do
      expect(fridge.presentation_light_intensity_choices).to eq((0..7).to_a)
      fridge.set_presentation_light_intensity(freezer, 8)
      expect(written).to eq([['PUT', 'Cooling/2/PresentationLightIntensity', { 'Value' => 8 }]])
    end

    it 'tells the app shows its presenter light with Status 10' do
      resources['State'] = { 'Status' => 10 }
      expect(fridge.presentation_light_intensity_offered?).to be(true)
    end

    it 'sets a zone intensity in Sabbath mode, even super cooling, while the app hides its presenter light',
       :aggregate_failures do
      resources['State'] = { 'Status' => 14 }
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect([fridge.settings_shown?, fridge.presentation_light_intensity_offered?]).to eq([false, false])
      fridge.set_presentation_light_intensity(freezer, 0)
      expect(written.size).to eq(1)
    end

    it 'tells the app shows no presentation light without a light state' do
      resources['Cooling']['PresentationLight'] = { 'Value' => 0 }
      expect([fridge.presentation_light_offered?, fridge.presentation_light_intensity_offered?]).to eq([false, false])
    end

    it "tells the app switches the light where only the dashboard's quick action shows it, never its intensity",
       :aggregate_failures do
      resources['State'] = { 'Status' => 8 }
      expect([fridge.presentation_light_offered?, fridge.presentation_light_intensity_offered?]).to eq([true, false])
      resources['State'] = { 'Status' => 5 }
      resources['Cooling'].merge!('Sabbath' => { 'Value' => 1 }, 'DustFilter' => { 'Value' => 3 })
      expect(fridge.presentation_light_offered?).to be(true)
    end

    it 'tells the app switches no light on a Rioja, though its light section shows', :aggregate_failures do
      expect([fridge.light_shown?, fridge.light_offered?]).to eq([true, false])
    end

    it 'tells the app hides the light in Sabbath mode with no notice ranked before it' do
      resources['Cooling']['Sabbath'] = { 'Value' => 1 }
      expect(fridge.presentation_light_offered?).to be(false)
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

    it 'posts it again 5 s after a 5xx or a lost connection, three times within the 15 s Timeout',
       :aggregate_failures do
      resources[:refusals] = [:drop, [502, {}, ''], [500, {}, '']]
      expect { fridge.set_target(fridge.zones.last, -20) }
        .to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '10000617000200FFEC' }]] * 3)
      expect(waits).to eq([5, 5])
    end

    it 'sends nothing for the current target, as the app does' do
      fridge.set_target(fridge.zones.last, -18)
      expect(written).to be_empty
    end

    it 'switches super freezing with ProcessAction 4' do
      fridge.set_super_mode(fridge.zones.last, true)
      expect(written).to eq([['PUT', 'State/ProcessAction', { 'ProcessAction' => 4 }]])
    end

    it 'sets a target outside the range the app fixes for each zone', :aggregate_failures do
      expect(fridge.target_choices(fridge.zones.first)).to eq((2..9).to_a)
      fridge.set_target(fridge.zones.first, 1)
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '100006170001000001' }]])
    end

    it 'sets no fraction of a degree, nor one out of 16 bits, which Oc85 does not carry', :aggregate_failures do
      expect { fridge.set_target(fridge.zones.first, 4.5) }.to raise_error(ArgumentError)
      expect { fridge.set_target(fridge.zones.first, 0x8000) }.to raise_error(ArgumentError)
      expect(written).to be_empty
    end

    it 'takes a whole Float, and refuses a fraction before reading anything', :aggregate_failures do
      zone = fridge.zones.first
      reads = fake.requests.size
      expect { fridge.set_target(zone, 4.5) }.to raise_error(ArgumentError)
      expect(fake.requests.size).to eq(reads)
      fridge.set_target(zone, 5.0)
      expect(written).to eq([['POST', 'Oc85/', { 'Request' => '100006170001000005' }]])
    end

    it 'writes no Cooling setting, an Opcode appliance having no Cooling resource', :aggregate_failures do
      zone = fridge.zones.last
      calls = { set_fan: [zone, true], set_vario_cool: [zone, true], set_mode: [:eco, true],
                set_presentation_light_intensity: [zone, 1], 'ice_maker=': [true], 'presentation_light=': [true],
                'humidity=': [:low], 'perfect_fresh=': [1], 'humidifier=': [1], 'door_alarm_delay=': [60] }
      calls.each { |name, args| expect { fridge.public_send(name, *args) }.to raise_error(Miele::Sdk::ActionUnavailableError) }
      expect(written).to be_empty
    end

    context 'with a KFN 37692 iDE' do
      let(:ident) do
        Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 21, 'ProtocolVersion' => 1,
                                                      'DeviceIdentLabel' => { 'TechType' => 'KFN 37692 iDE' })
      end

      it 'offers its fridge 3 to 9 °C and its freezer -26 to -15 °C' do
        expect(fridge.zones.map { fridge.target_choices(it) }).to eq([(3..9).to_a, (-26..-15).to_a])
      end
    end

    context 'with an FN 30402 i freezer' do
      let(:ident) do
        Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 20, 'ProtocolVersion' => 1,
                                                      'DeviceIdentLabel' => { 'TechType' => 'FN 30402 i' })
      end

      it 'offers it -28 to -15 °C' do
        expect(fridge.target_choices(fridge.zones.first)).to eq((-28..-15).to_a)
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
        expect([fridge.target_choices(first), fridge.target_choices(second)]).to eq([(5..20).to_a, [15]])
        fridge.set_target(second, 14)
        fridge.set_target(first, 20)
        expect(written.map { it[2]['Request'] }).to eq(%w[10000617000200000E 100006170001000014])
      end
    end
  end
end
