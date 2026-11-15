# frozen_string_literal: true

RSpec.describe Miele::Sdk::WarmingDrawer do
  subject(:drawer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 25, 'ProtocolVersion' => 2) }
  let(:resources) do
    { 'State' => { 'Status' => 2, 'RemoteEnable' => [15, 0, 1], 'ProgramID' => 0 },
      'services' => { 'CupsWarmUp' => { 'available' => true, 'activated' => false,
                                        'availableSourceDeviceIDs' => ['000111111111'] } },
      'ack' => '01' }
  end
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      path = request.path.delete_prefix("/Devices/#{fab}/")
      case request
      in { path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET' } then [200, {}, JSON.generate(served.fetch(path))]
      in { verb: 'POST', body: /"97880100"/ } then [200, {}, JSON.generate(Response: "97881101#{settings}")]
      in { verb: 'POST' } then [200, {}, JSON.generate(Response: "1101120#{served['ack'][1]}")]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def settings
    programs = [[40, 1, 4, 30, 50, 30, 35, 40, 45, 50], [60, 1, 6, 50, 80, 50, 60, 70, 75, 80],
                [65, 1, 3, 60, 85, 60, 65, 70, 80, 85], [80, 1, 12, 70, 90, 70, 75, 80, 85, 90]]
    [1, *programs.flatten, 2].pack('C*').unpack1('H*')
  end

  def requests = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Request') }

  def state(status, remote, **given) = resources['State'] = { 'Status' => status, 'RemoteEnable' => remote, **given }

  it 'switches on and off with 1101 while idle, as the app does', :aggregate_failures do
    state(10, [15, 0, 1])
    expect([drawer.switchable?, drawer.power_on_offered?, drawer.power_off_offered?]).to eq([true, true, true])
    drawer.power_on
    drawer.power_off
    expect(requests).to eq(%w[110102000102 110102000103])
  end

  it 'switches on once finished, or off with its door open' do
    state(7, [15, 0, 1])
    drawer.power_on
    state(1, [15, 0, 1], 'SignalDoor' => true)
    drawer.power_on
    expect(requests).to eq(%w[110102000102 110102000102])
  end

  it 'switches on while on or running, which the app does not offer', :aggregate_failures do
    expect(drawer.power_on_offered?).to be(false)
    drawer.power_on
    state(5, [15, 0, 1])
    expect(drawer.power_on_offered?).to be(false)
    drawer.power_on
    expect(requests).to eq(%w[110102000102 110102000102])
  end

  it 'switches off once off or finished, which the app does not offer', :aggregate_failures do
    state(1, [15, 0, 1])
    expect(drawer.power_off_offered?).to be(false)
    drawer.power_off
    state(7, [15, 0, 1])
    expect(drawer.power_off_offered?).to be(false)
    drawer.power_off
    expect(requests).to eq(%w[110102000103 110102000103])
  end

  it 'raises when the drawer refuses a write' do
    resources['ack'] = '02'
    expect { drawer.power_off }.to raise_error(Miele::Sdk::NotAcceptedError)
  end

  it 'switches on under local control, which the app does not offer', :aggregate_failures do
    state(1, [7, 0, 1])
    expect([drawer.switchable?, drawer.power_on_offered?]).to eq([false, false])
    drawer.power_on
    expect(requests).to eq(['110102000102'])
  end

  it 'tells the app offers no switch-off while the drawer is not connected' do
    state(255, [15, 0, 1])
    expect(drawer.power_off_offered?).to be(false)
  end

  it 'tells the app offers no program change without remote control, mobile start or not' do
    state(2, [0, 0, 1])
    expect(drawer.select_program_offered?).to be(false)
  end

  it 'switches off without mobile start, which the app does not offer', :aggregate_failures do
    state(5, [15, 0, 0])
    expect(drawer.power_off_offered?).to be(false)
    drawer.power_off
    expect(requests).to eq(['110102000103'])
  end

  it 'selects a program on 9781, Aus (0) too, but none Betriebsart does not define', :aggregate_failures do
    expect(drawer.select_program_offered?).to be(true)
    drawer.select_program(1)
    drawer.select_program(0)
    expect { drawer.select_program(5) }.to raise_error(ArgumentError)
    expect(requests).to eq(%w[97810200010100000000 97810200010000000000])
  end

  it 'changes the program under local control, or once one is chosen, which the app does not offer',
     :aggregate_failures do
    state(2, [7, 0, 1])
    expect(drawer.select_program_offered?).to be(false)
    drawer.select_program(1)
    state(2, [15, 0, 1], 'ProgramID' => 2)
    expect(drawer.select_program_offered?).to be(false)
    drawer.select_program(1)
    expect(requests.size).to eq(2)
  end

  it 'reads its state as the app does: an open door over running, a chosen program as programmed',
     :aggregate_failures do
    state(5, [15, 0, 1], 'SignalDoor' => true)
    expect(drawer.drawer_state).to eq(:door_open)
    state(1, [15, 0, 1], 'SignalDoor' => true)
    expect(drawer.drawer_state).to eq(:off_and_door_open)
    state(2, [15, 0, 1], 'ProgramID' => 1)
    expect(drawer.drawer_state).to eq(:programmed)
  end

  it 'reads its programs from 9788, durations in hours' do
    expect(drawer.programs.first)
      .to eq(described_class::Program.new(id: 1, min_hours: 1, max_hours: 4, temperatures: [30, 35, 40, 45, 50]))
  end

  it 'sets the temperature of the program, re-sending its remaining time', :aggregate_failures do
    state(5, [15, 0, 1], 'ProgramID' => 2, 'RemainingTime' => [1, 30])
    expect(drawer.target_temperature_offered?).to be(true)
    drawer.target_temperature = 70
    expect(requests).to eq(%w[97880100 9781020001021e000146])
  end

  it 'sets a temperature the program does not offer, but none its byte does not hold', :aggregate_failures do
    state(5, [15, 0, 1], 'ProgramID' => 2)
    expect(drawer.programs[1].temperatures).not_to include(65)
    drawer.target_temperature = 65
    expect { drawer.target_temperature = 256 }.to raise_error(ArgumentError)
    expect(requests.grep(/\A9781/)).to eq(%w[97810200010200000041])
  end

  it 'sets a temperature without mobile start, which the app does not offer', :aggregate_failures do
    state(5, [15, 0, 0], 'ProgramID' => 2)
    expect(drawer.target_temperature_offered?).to be(false)
    drawer.target_temperature = 60
    expect(requests.last).to eq('9781020001020000003c')
  end

  it 'writes no temperature or remaining time while State shows no program, Betriebsart 0 being Aus',
     :aggregate_failures do
    state(5, [15, 0, 1], 'ProgramID' => 0, 'TargetTemperature' => [6500])
    expect { drawer.target_temperature = 60 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { drawer.remaining_time = 90 }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(requests).to be_empty
  end

  it "sets the remaining time, re-sending the target, past the program's maximum too", :aggregate_failures do
    state(5, [15, 0, 1], 'ProgramID' => 3, 'TargetTemperature' => [6500])
    expect([drawer.remaining_time_offered?, drawer.programs[2].max_hours]).to eq([true, 3])
    drawer.remaining_time = 135
    drawer.remaining_time = 300
    expect(requests.grep(/\A9781/)).to eq(%w[9781020001030f000241 97810200010300000541])
  end

  it "sets a remaining time below the program's minimum, which the app's picker does not offer, but none negative",
     :aggregate_failures do
    state(5, [15, 0, 1], 'ProgramID' => 3, 'TargetTemperature' => [6500])
    expect(drawer.programs[2].min_hours).to eq(1)
    expect { drawer.remaining_time = -30 }.to raise_error(ArgumentError)
    drawer.remaining_time = 30
    drawer.remaining_time = 0
    expect(requests.grep(/\A9781/)).to eq(%w[9781020001031e000041 97810200010300000041])
  end

  it 'sends 255 as the target when State shows none, as the app does' do
    state(5, [15, 0, 1], 'ProgramID' => 3)
    drawer.remaining_time = 60
    expect(requests.last).to eq('978102000103000001ff')
  end

  it 'sets a remaining time unless the program is set or runs, which the app does not offer', :aggregate_failures do
    state(2, [15, 0, 1], 'ProgramID' => 3)
    expect(drawer.remaining_time_offered?).to be(false)
    drawer.remaining_time = 60
    expect(requests.last).to eq('978102000103000001ff')
  end

  it 'warms cups with a coffee maker, one the drawer does not list too, and stops', :aggregate_failures do
    expect(drawer.cups_warm_up_offered?).to be(true)
    drawer.cups_warm_up_source = '000111111111'
    drawer.cups_warm_up_source = nil
    drawer.cups_warm_up_source = '000222222222'
    expect(fake.requests.select { it.verb == 'PUT' }.map { JSON.parse(it.body)['sourceDeviceId'] })
      .to eq(['000111111111', nil, '000222222222'])
  end

  it 'tells the app offers no cup warm-up while disconnected, or where services lists none', :aggregate_failures do
    state(255, [15, 0, 1])
    expect(drawer.cups_warm_up_offered?).to be(false)
    state(2, [15, 0, 1])
    resources['services'] = {}
    expect(drawer.cups_warm_up_offered?).to be(false)
  end
end
