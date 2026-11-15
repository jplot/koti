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
      in { verb: 'POST', path: %r{/DOP/\z} } then [200, {}, served.fetch('DOP')]
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
    para = { 1 => dop2_field(:struct, { 4 => dop2_field(:u64, 0) }) }
    para[2] = dop2_field(:struct, { 3 => dop2_field(:u8, mode) }) if mode
    attributes = dop2_field(:struct, { 1 => dop2_field(:e16, 28) })
    dop2_leaf(2, 1574, { 3 => dop2_field(:struct, para), 6 => attributes }, idx2: 1)
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

    it 'stops, which the app does not offer', :aggregate_failures do
      expect(washer.supported_requests).not_to include(2)
      washer.stop
      expect(written).to eq([user_request(2)])
    end

    it 'starts with the door only closed, which the app does not offer', :aggregate_failures do
      leaves['2/1585'] = device_context(door: 2)
      expect(washer.supported_requests).not_to include(1)
      washer.start
      expect(written).to eq([user_request(1)])
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

    it 'keeps request 8 when 2/1574 shows no delayed-start mode, which the app takes as relative' do
      leaves['2/1585'] = device_context(requests: [1, 2, 8])
      leaves['2/1574?idx1=0&idx2=1'] = ps_context(mode: nil)
      expect(washer.supported_requests).to eq([1, 8])
    end
  end

  context 'when its program waits for its start time' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    it 'stops it to edit with request 12102', :aggregate_failures do
      leaves['2/1585'] = device_context(requests: [1, 2, 12_102])
      leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
      expect(washer.stop_to_edit_offered?).to be(true)
      washer.stop_to_edit
      expect(written).to eq([user_request(12_102)])
    end
  end

  it 'stops a running program to edit it, which the app does not offer', :aggregate_failures do
    leaves['2/1585'] = device_context(requests: [2, 12_102])
    leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
    expect(washer.stop_to_edit_offered?).to be(false)
    washer.stop_to_edit
    expect(written).to eq([user_request(12_102)])
  end

  it 'extends the anti-crease phase with request 12144 when the washer offers it' do
    leaves['2/1585'] = device_context(requests: [2, 12_144])
    leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
    washer.extend_anti_crease
    expect(written).to eq([user_request(12_144)])
  end

  context 'when it runs' do
    before { leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) }) }

    it 'pauses with request 3, stops with 2 and silences its end signal with 28', :aggregate_failures do
      expect(washer.stop_end_signal_offered?).to be(true)
      washer.pause
      washer.stop
      washer.stop_end_signal
      expect(written.map(&:last)).to eq([user_request(3), user_request(2), user_request(28)].map(&:last))
    end

    it 'tells the app offers no end signal stop unless 2/1585 lists request 28' do
      leaves['2/1585'] = device_context(requests: [1, 2, 3])
      expect(washer.stop_end_signal_offered?).to be(false)
    end
  end

  context 'without remote control' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [0, 0, 0], 'StandbyState' => 1 } }

    it 'pauses, while the app offers only stop', :aggregate_failures do
      leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
      expect(washer.supported_requests).to eq([2])
      washer.pause
      expect(written).to eq([user_request(3)])
    end
  end

  context 'when it sleeps deeply' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'stops and wakes, while the app offers no request and does not wake this washer', :aggregate_failures do
      leaves['2/1583?idx1=0&idx2=0'] = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
      expect([washer.supported_requests, washer.wake_offered?]).to eq([[], false])
      washer.stop
      washer.wake
      expect(written.map { it[1] }).to eq(%w[DOP2/2/1583 State])
    end
  end

  context 'when a Premium washer sleeps deeply' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4,
                                                    'DeviceIdentLabel' => { 'TechType' => 'WWR860', 'SWIDs' => [] })
    end
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'wakes it with DeviceAction 2', :aggregate_failures do
      expect(washer.wake_offered?).to be(true)
      washer.wake
      expect(written.map { [it[1], JSON.parse(it[2])] }).to eq([['State', { 'DeviceAction' => 2 }]])
    end

    it 'tells the app wakes it only from a deep sleep' do
      state['StandbyState'] = 1
      expect(washer.wake_offered?).to be(false)
    end
  end

  context 'when a Discovery washer on older software sleeps deeply' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4,
                                                    'DeviceIdentLabel' => { 'TechType' => 'WWD020', 'SWIDs' => [5700] })
    end
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'wakes it, which the app does not offer', :aggregate_failures do
      expect(washer.wake_offered?).to be(false)
      washer.wake
      expect(written.map { it[1] }).to eq(['State'])
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

    it 'switches off with 1/0/0 on 2/1586', :aggregate_failures do
      leaves['2/1585'] = device_context(process: 10)
      expect(washer.power_off_offered?).to be(true)
      washer.power_off
      expect(written).to eq([['PUT', 'DOP2/2/1586', combi_state(1, 0, 0)]])
    end

    it 'switches off while the program runs, which the app does not offer', :aggregate_failures do
      expect(washer.power_off_offered?).to be(false)
      washer.power_off
      expect(written).to eq([['PUT', 'DOP2/2/1586', combi_state(1, 0, 0)]])
    end
  end

  it 'selects a program on 2/1577 with selection type 0' do
    leaves['2/1577?idx1=0&idx2=0'] = dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 0), 3 => dop2_field(:e8, 2) })
    washer.select_program(28)
    fields = { 1 => dop2_field(:e16, 28), 3 => dop2_field(:e8, 0) }
    expect(written).to eq([['PUT', 'DOP2/2/1577', dop2_leaf(2, 1577, fields)]])
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

    it "writes a Dop1 washer's program on 8201 and raises on a refused Ack", :aggregate_failures do
      leaves['DOP'] = '{"Response":"82011201"}'
      washer.select_program(28)
      leaves['DOP'] = '{"Response":"82011202"}'
      expect { washer.select_program(28) }.to raise_error(Miele::Sdk::NotAcceptedError)
      expect(JSON.parse(written.first.last)).to eq('Request' => "82010100011c00#{'00' * 22}")
    end

    it 'stops and pauses with ProcessAction, while the app offers stop alone', :aggregate_failures do
      expect(washer.supported_requests).to eq([2])
      washer.stop
      washer.pause
      expect(written.map { JSON.parse(it[2]) }).to eq([{ 'ProcessAction' => 2 }, { 'ProcessAction' => 3 }])
    end

    it 'neither silences its end signal nor switches off, its protocol having no DOP2 leaf', :aggregate_failures do
      expect { washer.stop_end_signal }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { washer.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { washer.stop_to_edit }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { washer.extend_anti_crease }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect([washer.stop_end_signal_offered?, washer.power_off_offered?, washer.wake_offered?])
        .to eq([false, false, false])
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

  context 'with an Opcode washer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 1) }

    it 'neither selects a program nor sets its parameters, having no selection object', :aggregate_failures do
      expect { washer.select_program(28) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { washer.set_parameters(spin_speed: 1400) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { washer.start_delayed(Time.new(2026, 10, 31, 21, 30)) }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(washer.set_parameters_offered?).to be(false)
      expect(written).to be_empty
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
