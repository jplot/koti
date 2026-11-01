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

  it 'switches on and off with 1101 while idle, as the app does' do
    state(10, [15, 0, 1])
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

  it 'refuses to switch on while on or running, as the app does', :aggregate_failures do
    expect { drawer.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
    state(5, [15, 0, 1])
    expect { drawer.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(requests).to be_empty
  end

  it 'refuses to switch off once off or finished, as the app does', :aggregate_failures do
    state(1, [15, 0, 1])
    expect { drawer.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
    state(7, [15, 0, 1])
    expect { drawer.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(requests).to be_empty
  end

  it 'raises when the drawer refuses a write' do
    resources['ack'] = '02'
    expect { drawer.power_off }.to raise_error(Miele::Sdk::NotAcceptedError)
  end

  it 'refuses to switch on under local control', :aggregate_failures do
    state(1, [7, 0, 1])
    expect { drawer.power_on }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(requests).to be_empty
  end

  it 'refuses to switch off without mobile start' do
    state(5, [15, 0, 0])
    expect { drawer.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'selects a program on 9781' do
    drawer.select_program(1)
    expect(requests).to eq(['97810200010100000000'])
  end

  it 'refuses a program change under local control' do
    state(2, [7, 0, 1])
    expect { drawer.select_program(1) }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'refuses a program change once a program is chosen, as the app does' do
    state(2, [15, 0, 1], 'ProgramID' => 2)
    expect { drawer.select_program(1) }.to raise_error(Miele::Sdk::ActionUnavailableError)
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

  it 'sets the temperature of the program, re-sending its remaining time' do
    state(5, [15, 0, 1], 'ProgramID' => 2, 'RemainingTime' => [1, 30])
    drawer.target_temperature = 70
    expect(requests).to eq(%w[97880100 9781020001021e000146])
  end

  it 'refuses a temperature the program does not offer' do
    state(5, [15, 0, 1], 'ProgramID' => 2)
    expect { drawer.target_temperature = 65 }.to raise_error(ArgumentError)
  end

  it "sets the remaining time, re-sending the target and keeping to the program's maximum" do
    state(5, [15, 0, 1], 'ProgramID' => 3, 'TargetTemperature' => [6500])
    drawer.remaining_time = 135
    drawer.remaining_time = 300
    expect(requests).to eq(%w[97880100 9781020001030f000241 97880100 97810200010300000341])
  end

  it 'sends 255 as the target when State shows none, as the app does' do
    state(5, [15, 0, 1], 'ProgramID' => 3)
    drawer.remaining_time = 60
    expect(requests.last).to eq('978102000103000001ff')
  end

  it 'refuses a remaining time unless the program is set or runs' do
    state(2, [15, 0, 1], 'ProgramID' => 3)
    expect { drawer.remaining_time = 60 }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'warms cups with a coffee maker the drawer lists, and stops', :aggregate_failures do
    drawer.cups_warm_up_source = '000111111111'
    drawer.cups_warm_up_source = nil
    expect { drawer.cups_warm_up_source = '000222222222' }.to raise_error(ArgumentError)
    expect(fake.requests.select { it.verb == 'PUT' }.map { [it.path, JSON.parse(it.body)] })
      .to eq([["/Devices/#{fab}/services/CupsWarmUp", { 'activated' => true, 'sourceDeviceId' => '000111111111' }],
              ["/Devices/#{fab}/services/CupsWarmUp", { 'activated' => false }]])
  end
end
