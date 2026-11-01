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
      in { verb: 'POST', body: /89060100"/ } then [200, {}, '{"Response":"890611000105ff00"}']
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

  it 'pauses a Dop1 dishwasher with ProcessAction 2 on its state' do
    dishwasher.pause
    expect(written).to eq([['PUT', 'State', state.merge('ProcessAction' => 2)]])
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

  it 'sets the extras on 8906 for the program State shows', :aggregate_failures do
    dishwasher.set_extras(:eco, :additional_drying)
    expect { dishwasher.set_extras(:quick) }.to raise_error(ArgumentError)
    expect(dop1_requests).to eq(['89060100010d4200'])
  end

  it 'refuses a delayed start while the program runs, as the app does' do
    expect { dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30)) }
      .to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  context 'when its program is selected' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'ProgramID' => 13 } }

    it 'opens the door under mobile start' do
      dishwasher.open_door
      expect(dop1_requests).to eq(['140402000102'])
    end

    it 'delays the start on 8909 in minutes and hours, sending no start request after' do
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 31, 20, 0, 30))
      dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30))
      expect(dop1_requests).to eq(['89090200011e0101'])
    end
  end

  context 'with the door open' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => true, 'ProgramID' => 13 } }

    it 'refuses to open it, as the app does', :aggregate_failures do
      expect { dishwasher.open_door }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written).to be_empty
    end
  end
end
