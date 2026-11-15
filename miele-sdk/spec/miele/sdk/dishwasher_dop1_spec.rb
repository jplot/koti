# frozen_string_literal: true

RSpec.describe Miele::Sdk::Dishwasher do
  subject(:dishwasher) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) do
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 7, 'ProtocolVersion' => 2,
                                                  'DeviceIdentLabel' => { 'TechType' => 'G7310' })
  end
  let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'ProgramID' => 13 } }
  let(:fake) do
    current = state
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(current)]
      in { verb: 'POST', body: /89060100"/ } then [200, {}, JSON.generate(Response: extras_read)]
      in { verb: 'POST', body: /89090100"/ }
        now[0] = Time.new(2026, 10, 31, 20, 1, 1)
        [200, {}, '{"Response":"8909110001000001"}']
      else [200, {}, '{}']
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

  def dop1_requests = written.map { it.last['Request'] }

  def now = @now ||= [Time.new(2026, 10, 31, 20, 0, 58)]

  def extras_read = '890611000105ff00'

  it 'pauses a Dop1 dishwasher with ProcessAction 2 on its state' do
    dishwasher.pause
    expect(written).to eq([['PUT', 'State', state.merge('ProcessAction' => 2)]])
  end

  it 'refuses to wake it, the app having no wake request for a Dop1 dishwasher', :aggregate_failures do
    state['Status'] = 1
    expect { dishwasher.wake }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  context 'when the app gives each request its own token' do
    before do
      Miele::Sdk.config.read_timeout = 30
      dishwasher.fab
    end

    it 'reads and writes State within 1 s each, as ExecuteProgramForDop1Action' do
      timeouts = read_timeouts
      dishwasher.pause
      expect(timeouts).to eq([1, 1])
    end

    it 'reads 8906 within 5 s to select a program, and writes it with no token of its own' do
      timeouts = read_timeouts
      dishwasher.select_program(28)
      expect(timeouts).to eq([5, 30])
    end

    it 'reads 8906, then State, within 5 s each to set the extras, as SelectExtrasForDop1Action' do
      timeouts = read_timeouts
      dishwasher.set_extras(:eco)
      expect(timeouts).to eq([5, 5, 30])
    end

    it 'reads 8909 within 5 s before the delayed start, as SetStartTimeForDelayStartForDop1Action' do
      timeouts = read_timeouts
      dishwasher.start_delayed(Time.now + 3600)
      expect(timeouts).to eq([5, 30])
    end

    it 'opens the door within 5 s, as OpenDoorForDop1Action' do
      timeouts = read_timeouts
      dishwasher.open_door
      expect(timeouts).to eq([5])
    end
  end

  context 'when State carries keys the app does not know' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1], 'ProgramName' => 'Eco', 'Light' => nil } }

    it "writes back only what the app's DeviceStateDto keeps" do
      dishwasher.pause
      expect(written.last.last).to eq('Status' => 5, 'RemoteEnable' => [15, 0, 1], 'ProcessAction' => 2)
    end
  end

  context 'when its program waits' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'ProgramID' => 13 } }

    it 'stops with ProcessAction 2 though only cancel is offered, as the app does' do
      dishwasher.stop
      expect(written.map(&:last)).to eq([state.merge('ProcessAction' => 2)])
    end

    it 'cancels with 128' do
      dishwasher.cancel
      expect(written.map(&:last)).to eq([state.merge('ProcessAction' => 128)])
    end
  end

  it 'selects a program with the read request carrying data, keeping the extras past bit 5, as the app does' do
    dishwasher.select_program(28)
    expect(dop1_requests).to eq(%w[89060100 89060100011cc000])
  end

  it 'writes the extras on 8906 as read, its reserve bits kept, for the program State shows', :aggregate_failures do
    expect(dishwasher.offered_extras).to eq(%i[short eco dry intensive_low soak prerinse additional_drying])
    dishwasher.set_extras(:eco, :additional_drying)
    expect { dishwasher.set_extras(:quick) }.to raise_error(ArgumentError)
    expect(dop1_requests).to eq(%w[89060100 89060100010dc200])
    expect(fake.requests.map(&:verb).last(3)).to eq(%w[POST GET POST])
  end

  context 'when 8906 shows every extras bit set' do
    def extras_read = '890611000105ffff'

    it 'writes back its nine reserve bits as read, and each extra as named, additional drying off too' do
      dishwasher.set_extras(:eco)
      expect(dop1_requests.last).to eq('89060100010d82ff')
    end
  end

  it 'writes no setting, a Dop1 dishwasher having no 2/105', :aggregate_failures do
    expect { dishwasher.write_setting(20_002, 1) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect { dishwasher.auto_dos = true }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  it 'delays the start while the program runs, which the app does not offer', :aggregate_failures do
    expect(dishwasher.start_delayed_offered?).to be(false)
    dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30))
    expect(dop1_requests.last).to start_with('8909')
  end

  it 'counts the delay from when 8909 is answered, as GetTimeOffsetToNow reads the clock then' do
    allow(Time).to receive(:now) { now.first }
    dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30))
    expect(dop1_requests).to eq(%w[89090100 89090200011d0101])
  end

  context 'when its program is selected' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'ProgramID' => 13 } }

    it 'opens the door under mobile start', :aggregate_failures do
      expect([dishwasher.open_door_offered?, dishwasher.start_delayed_offered?]).to eq([true, true])
      dishwasher.open_door
      expect(dop1_requests).to eq(['140402000102'])
    end

    it 'delays the start on 8909 in minutes and hours, sending no start request after' do
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 31, 20, 0, 30))
      dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30))
      expect(dop1_requests).to eq(%w[89090100 89090200011e0101])
    end
  end

  context 'with the door open' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => true, 'ProgramID' => 13 } }

    it 'opens it again, which the app does not offer', :aggregate_failures do
      expect(dishwasher.open_door_offered?).to be(false)
      dishwasher.open_door
      expect(dop1_requests).to eq(['140402000102'])
    end
  end
end
