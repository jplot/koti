# frozen_string_literal: true

RSpec.describe Miele::Sdk::WashingMachine do
  subject(:washer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4) }
  let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }
  let(:leaves) { { '2/1585' => device_context } }
  let(:fake) do
    served = leaves
    current = state
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(current)]
      in { verb: 'GET', path: %r{/DOP2/(.+)\z} } then [200, {}, served.fetch(Regexp.last_match(1))]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def device_context(requests: [1, 2, 3, 28], door: 3, process: 4)
    dop2_leaf(2, 1585, { 1 => dop2_field(:struct, { 3 => dop2_field(:e8, process) }),
                         6 => dop2_field(:struct, { 1 => dop2_field(:e8, door) }),
                         9 => dop2_field(:e16_array, requests) })
  end

  def written
    fake.requests.reject { it.verb == 'GET' }.map { [it.verb, it.path.delete_prefix("/Devices/#{fab}/"), it.body] }
  end

  def user_request(id) = ['PUT', 'DOP2/2/1583', dop2_leaf(2, 1583, { 1 => dop2_field(:e16, id) })]

  def ps_context(mode:)
    para = { 2 => dop2_field(:struct, { 3 => dop2_field(:u8, mode) }) }
    dop2_leaf(2, 1574, { 3 => dop2_field(:struct, para) }, idx2: 1)
  end

  def combi_state(appliance, operation, process)
    dop2_leaf(2, 1586, { 1 => dop2_field(:e8, appliance), 2 => dop2_field(:e8, operation),
                         3 => dop2_field(:e8, process) })
  end

  context 'when its program is selected with the door locked' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    before { leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) }) }

    it 'starts with request 1 written back on the leaf it read' do
      washer.start
      expect(written).to eq([user_request(1)])
    end

    it 'refuses to stop, as the app does' do
      expect { washer.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end

    it 'refuses to start with the door only closed', :aggregate_failures do
      leaves['2/1585'] = device_context(door: 2)
      expect { washer.start }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written).to be_empty
    end
  end

  context 'when its selected program could start later' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    it 'offers request 8 only while 2/1574 shows a delayed-start mode', :aggregate_failures do
      leaves['2/1585'] = device_context(requests: [1, 2, 8])
      leaves['2/1574?idx1=0&idx2=1'] = ps_context(mode: 0)
      expect(washer.supported_requests).to eq([1])
      leaves['2/1574?idx1=0&idx2=1'] = ps_context(mode: 1)
      expect(washer.supported_requests).to eq([1, 8])
    end
  end

  context 'when its program waits for its start time' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    it 'stops it to edit with request 12102' do
      leaves['2/1585'] = device_context(requests: [1, 2, 12_102])
      leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
      washer.stop_to_edit
      expect(written).to eq([user_request(12_102)])
    end
  end

  it 'refuses to stop a running program to edit it' do
    leaves['2/1585'] = device_context(requests: [2, 12_102])
    expect { washer.stop_to_edit }.to raise_error(Miele::Sdk::ActionUnavailableError)
  end

  it 'extends the anti-crease phase with request 12144 when the washer offers it' do
    leaves['2/1585'] = device_context(requests: [2, 12_144])
    leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
    washer.extend_anti_crease
    expect(written).to eq([user_request(12_144)])
  end

  context 'when it runs' do
    before { leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) }) }

    it 'pauses with request 3, stops with 2 and silences its end signal with 28' do
      washer.pause
      washer.stop
      washer.stop_end_signal
      expect(written.map(&:last)).to eq([user_request(3), user_request(2), user_request(28)].map(&:last))
    end
  end

  context 'without remote control' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [0, 0, 0], 'StandbyState' => 1 } }

    it 'offers only stop, as the app does' do
      expect { washer.pause }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when it sleeps deeply' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'offers no request' do
      expect { washer.stop }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end

    it 'refuses to wake a washer the app does not wake' do
      expect { washer.wake }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when a Premium washer sleeps deeply' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4,
                                                    'DeviceIdentLabel' => { 'TechType' => 'WWR860', 'SWIDs' => [] })
    end
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'wakes it with DeviceAction 2' do
      washer.wake
      expect(written.map { [it[1], JSON.parse(it[2])] }).to eq([['State', { 'DeviceAction' => 2 }]])
    end
  end

  context 'when a Discovery washer on older software sleeps deeply' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4,
                                                    'DeviceIdentLabel' => { 'TechType' => 'WWD020', 'SWIDs' => [5700] })
    end
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'refuses to wake it, as the app does' do
      expect { washer.wake }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  it 'acknowledges a message on 2/138, read at 0/0' do
    leaves['2/138?idx1=0&idx2=0'] = dop2_leaf(2, 138, { 2 => dop2_field(:e16, 0), 5 => dop2_field(:e8, 0) })
    washer.acknowledge(message: 3, option: 1)
    fields = { 2 => dop2_field(:e16, 3), 5 => dop2_field(:e8, 1) }
    expect(written).to eq([['PUT', 'DOP2/2/138', dop2_leaf(2, 138, fields)]])
  end

  context 'when its program is done' do
    let(:state) { { 'Status' => 7, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1, 'ProgramPhase' => 0 } }

    before { leaves['2/1586?idx1=0&idx2=0'] = combi_state(2, 3, 10) }

    it 'switches off with 1/0/0 on 2/1586' do
      leaves['2/1585'] = device_context(process: 10)
      washer.power_off
      expect(written).to eq([['PUT', 'DOP2/2/1586', combi_state(1, 0, 0)]])
    end

    it 'refuses to switch off while the program runs' do
      expect { washer.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  it 'sets the anti-crease setting on 2/105, read at idx1 12037 idx2 0' do
    leaves['2/105?idx1=12037&idx2=0'] =
      dop2_leaf(2, 105, { 1 => dop2_field(:e16, 12_037), 4 => dop2_field(:i16, 0) }, idx1: 12_037)
    washer.anti_crease = 2
    fields = { 1 => dop2_field(:e16, 12_037), 4 => dop2_field(:i16, 2) }
    expect(written).to eq([['PUT', 'DOP2/2/105', dop2_leaf(2, 105, fields, idx1: 12_037)]])
  end

  it 'sets the TwinDos filling levels on services' do
    washer.twin_dos_levels = [{ number: 1, percent: 50 }]
    expect(written).to eq([['POST', 'services/TwinDos', '[{"number":1,"containerFillingLevelPercent":50}]']])
  end

  context 'with a Dop1 washer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 2) }
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false } }

    it 'stops with ProcessAction 2 alone and never pauses', :aggregate_failures do
      washer.stop
      expect { washer.pause }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written.map { [it[1], JSON.parse(it[2])] }).to eq([['State', { 'ProcessAction' => 2 }]])
    end
  end

  context 'with a Dop1 washer whose program is selected under mobile start' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 2) }
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'StartTime' => [0, 0] } }

    it 'starts without a start time and offers request 8 once one is set', :aggregate_failures do
      washer.start
      state['StartTime'] = [1, 30]
      expect(washer.supported_requests).to eq([8])
      expect(written.map { [it[1], JSON.parse(it[2])] }).to eq([['State', { 'ProcessAction' => 1 }]])
    end
  end

  context 'with a Dop1 washer waiting to start' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 2) }
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false } }

    it 'starts with ProcessAction 1' do
      washer.start
      expect(written.map { [it[1], JSON.parse(it[2])] }).to eq([['State', { 'ProcessAction' => 1 }]])
    end
  end
end
