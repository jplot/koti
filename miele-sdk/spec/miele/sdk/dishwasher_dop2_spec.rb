# frozen_string_literal: true

RSpec.describe Miele::Sdk::Dishwasher do
  subject(:dishwasher) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) do
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 7, 'ProtocolVersion' => 4, 'AppSupport' => 16,
                                                  'DeviceIdentLabel' => { 'TechType' => 'G7310' })
  end
  let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1, 'SignalDoor' => false } }
  let(:leaves) { {} }
  let(:fake) do
    served = leaves
    current = state
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(current)]
      in { verb: 'GET', path: %r{/DOP2/(.+)\z} }
        leaf = Regexp.last_match(1)
        [200, {}, served.fetch(leaf) { default_leaf(leaf) }]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def default_leaf(path)
    case path
    when '2/1583?idx1=0&idx2=0' then dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
    when '2/131?idx1=0&idx2=1' then dop2_leaf(2, 131, {}, idx2: 1)
    when '2/1585?idx1=0&idx2=1' then dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [1, 2, 3, 8, 52]) }, idx2: 1)
    when %r{\A2/1586\?idx1=0&idx2=(\d)} then combi_state(Regexp.last_match(1).to_i, 2, 0, 0)
    end
  end

  def combi_state(idx2, appliance, operation, process)
    dop2_leaf(2, 1586, { 1 => dop2_field(:e8, appliance), 2 => dop2_field(:e8, operation),
                         3 => dop2_field(:e8, process) }, idx2:)
  end

  def extras(**on) = (1..9).to_h { [it, dop2_field(:bool, on.fetch(it, false))] }

  def select(idx1, idx2, **given)
    values = { prog: 0, type: 0, mode: 0, start: 0, extras: }.merge(given)
    para = { 1 => dop2_field(:u64, values[:start]), 2 => dop2_field(:u8, values[:mode]),
             3 => dop2_field(:struct, values[:extras]) }
    fields = { 1 => dop2_field(:e16, values[:prog]), 3 => dop2_field(:e8, values[:type]),
               4 => dop2_field(:struct, para) }
    dop2_leaf(2, 1577, fields, idx1:, idx2:)
  end

  def context(idx2, bits: 0, mode: 2, prog: 13)
    para = { 2 => dop2_field(:struct, { 2 => dop2_field(:u8, bits), 3 => dop2_field(:u8, mode) }) }
    dop2_leaf(2, 1574, { 1 => dop2_field(:struct, para), 6 => dop2_field(:struct, { 1 => dop2_field(:e16, prog) }) },
              idx2:)
  end

  def written
    fake.requests.reject { it.verb == 'GET' }.map { [it.verb, it.path.delete_prefix("/Devices/#{fab}/"), it.body] }
  end

  def user_request(id) = ['PUT', 'DOP2/2/1583', dop2_leaf(2, 1583, { 1 => dop2_field(:e16, id) })]

  it 'starts with request 1 written back on the leaf it read' do
    dishwasher.start
    expect(written).to eq([user_request(1)])
  end

  it 'refuses to start while info 700 is shown', :aggregate_failures do
    leaves['2/131?idx1=0&idx2=1'] =
      dop2_leaf(2, 131, { 1 => dop2_field(:struct_array, [{ 1 => dop2_field(:e16, 700) }]) }, idx2: 1)
    expect { dishwasher.start }.to raise_error(Miele::Sdk::ActionUnavailableError)
    expect(written).to be_empty
  end

  context 'with the door open' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1, 'SignalDoor' => true } }

    it 'refuses to start' do
      expect { dishwasher.start }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when it runs without mobile start' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 0], 'StandbyState' => 1 } }

    it 'stops without mobile start, but neither pauses nor cancels while its details bar shows pause',
       :aggregate_failures do
      dishwasher.stop
      expect { dishwasher.pause }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect { dishwasher.cancel }.to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written.map(&:last)).to eq([user_request(2).last])
    end
  end

  context 'when it runs and offers only to cancel' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    before { leaves['2/1585?idx1=0&idx2=1'] = dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [52]) }, idx2: 1) }

    it "stops all the same, as the app's Stop quick action does" do
      dishwasher.stop
      expect(written.map(&:last)).to eq([user_request(2).last])
    end

    it 'cancels from its details bar' do
      dishwasher.cancel
      expect(written.map(&:last)).to eq([user_request(52).last])
    end
  end

  context 'when its program is selected under mobile start and offers only to cancel' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    it 'cancels, as its details bar allows from Status 3' do
      leaves['2/1585?idx1=0&idx2=1'] = dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [52]) }, idx2: 1)
      dishwasher.cancel
      expect(written.map(&:last)).to eq([user_request(52).last])
    end
  end

  context 'when it waits for its start time without remote control or mobile start' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [14, 0, 0], 'StandbyState' => 1 } }

    it 'refuses to cancel, as its details bar does' do
      leaves['2/1585?idx1=0&idx2=1'] = dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [52]) }, idx2: 1)
      expect { dishwasher.cancel }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when it waits for its start time under remote control, without mobile start' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 0], 'StandbyState' => 1 } }

    it 'cancels, as its details bar allows' do
      leaves['2/1585?idx1=0&idx2=1'] = dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [52]) }, idx2: 1)
      dishwasher.cancel
      expect(written.map(&:last)).to eq([user_request(52).last])
    end
  end

  context 'when it is locked or asleep waiting to start' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [7, 0, 1], 'StandbyState' => 1 } }

    it 'refuses to cancel, as its details bar hides itself', :aggregate_failures do
      leaves['2/1585?idx1=0&idx2=1'] = dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [52]) }, idx2: 1)
      expect { dishwasher.cancel }.to raise_error(Miele::Sdk::ActionUnavailableError)
      state.merge!('RemoteEnable' => [15, 0, 1], 'StandbyState' => 2)
      expect { dishwasher.cancel }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when it runs under mobile start' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    it 'pauses with request 3' do
      dishwasher.pause
      expect(written.map(&:last)).to eq([user_request(3).last])
    end

    it 'refuses a delayed start, as the app does', :aggregate_failures do
      expect { dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30)) }
        .to raise_error(Miele::Sdk::ActionUnavailableError)
      expect(written).to be_empty
    end
  end

  context 'when its program is selected without mobile start' do
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 0], 'StandbyState' => 1 } }

    it 'refuses a delayed start, as the app does' do
      expect { dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30)) }
        .to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when paused under mobile start' do
    let(:state) { { 'Status' => 6, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 1 } }

    it 'resumes with request 1, as the app does' do
      dishwasher.resume
      expect(written.map(&:last)).to eq([user_request(1).last])
    end
  end

  it 'sets a delayed start in minutes when the dishwasher counts down, then sends request 8' do
    allow(Time).to receive(:now).and_return(Time.new(2026, 10, 31, 20, 0, 30))
    leaves['2/1577?idx1=1&idx2=2'] = select(1, 2)
    leaves['2/1574?idx1=0&idx2=1'] = context(1, bits: 33)
    dishwasher.start_delayed(Time.new(2026, 10, 31, 21, 30))
    expect(written.map(&:last)).to eq([select(1, 2, type: 2, mode: 1, start: 90), user_request(8).last])
  end

  it 'sets a delayed start as local seconds since 1970 when the dishwasher counts to a time' do
    allow(Time).to receive(:now).and_return(Time.new(2026, 10, 31, 22, 0, 0))
    leaves['2/1577?idx1=1&idx2=2'] = select(1, 2)
    leaves['2/1574?idx1=0&idx2=1'] = context(1, bits: 2)
    target = Time.new(2026, 11, 1, 6, 15)
    dishwasher.start_delayed(Time.new(2026, 10, 31, 6, 15))
    expect(written.first.last).to eq(select(1, 2, type: 2, mode: 2, start: target.to_i + target.utc_offset))
  end

  context 'when the clocks have gone back an hour today' do
    around do |example|
      zone = ENV.fetch('TZ', nil)
      ENV['TZ'] = 'Europe/Paris'
      example.run
    ensure
      ENV['TZ'] = zone
    end

    before do
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 25, 4, 0, 0))
      leaves['2/1577?idx1=1&idx2=2'] = select(1, 2)
    end

    it 'counts the minutes on the wall clock, as the app does' do
      leaves['2/1574?idx1=0&idx2=1'] = context(1, bits: 33)
      dishwasher.start_delayed(Time.new(2026, 10, 25, 7, 0))
      expect(written.first.last).to eq(select(1, 2, type: 2, mode: 1, start: 180))
    end

    it 'sends the wall-clock time of the day' do
      leaves['2/1574?idx1=0&idx2=1'] = context(1, bits: 2)
      dishwasher.start_delayed(Time.new(2026, 10, 25, 7, 0))
      expect(written.first.last).to eq(select(1, 2, type: 2, mode: 2, start: Time.utc(2026, 10, 25, 7).to_i))
    end
  end

  it 'selects a program on 2/1577 with selection type 0' do
    leaves['2/1577?idx1=0&idx2=0'] = select(0, 0)
    dishwasher.select_program(28)
    expect(written).to eq([['PUT', 'DOP2/2/1577', select(0, 0, prog: 28)]])
  end

  it 'sets the extras this model writes, leaves the others as read, and keeps the start mode it reads',
     :aggregate_failures do
    leaves['2/1577?idx1=0&idx2=0'] = select(0, 0, extras: extras(5 => true))
    leaves['2/1574?idx1=0&idx2=0'] = context(0, mode: 1)
    dishwasher.set_extras(:express, :dry)
    expect { dishwasher.set_extras(:quick) }.to raise_error(ArgumentError)
    expect(written.map(&:last))
      .to eq([select(0, 0, prog: 13, type: 2, mode: 1, extras: extras(1 => true, 4 => true, 5 => true))])
  end

  it 'refuses extras when 2/1577 carries none, sending nothing', :aggregate_failures do
    para = { 1 => dop2_field(:u64, 0), 2 => dop2_field(:u8, 0) }
    leaves['2/1577?idx1=0&idx2=0'] = dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 0), 4 => dop2_field(:struct, para) })
    leaves['2/1574?idx1=0&idx2=0'] = context(0)
    expect { dishwasher.set_extras(:express) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'switches AutoDos on 2/105 at 20052' do
    leaves['2/105?idx1=20052&idx2=1'] =
      dop2_leaf(2, 105, { 1 => dop2_field(:e16, 20_052), 4 => dop2_field(:i16, 0) }, idx1: 20_052, idx2: 1)
    dishwasher.auto_dos = true
    fields = { 1 => dop2_field(:e16, 20_052), 4 => dop2_field(:i16, 1) }
    expect(written).to eq([['PUT', 'DOP2/2/105', dop2_leaf(2, 105, fields, idx1: 20_052, idx2: 1)]])
  end

  it 'writes a setting at its SF id on a G7, refusing one the app writes on a PFD10 only', :aggregate_failures do
    leaves['2/105?idx1=20002&idx2=1'] =
      dop2_leaf(2, 105, { 1 => dop2_field(:e16, 20_002), 4 => dop2_field(:i16, 0) }, idx1: 20_002, idx2: 1)
    dishwasher.write_setting(20_002, 12)
    expect { dishwasher.write_setting(20_064, 1) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    fields = { 1 => dop2_field(:e16, 20_002), 4 => dop2_field(:i16, 12) }
    expect(written).to eq([['PUT', 'DOP2/2/105', dop2_leaf(2, 105, fields, idx1: 20_002, idx2: 1)]])
  end

  it 'leaves the abort state as the app does' do
    dishwasher.leave_abort
    expect(written).to eq([['PUT', 'DOP2/2/1586', combi_state(1, 4, 5, 1)]])
  end

  it 'acknowledges an info on 2/138' do
    leaves['2/138?idx1=0&idx2=1'] = dop2_leaf(2, 138, { 1 => dop2_field(:e16, 0), 5 => dop2_field(:e8, 0) }, idx2: 1)
    dishwasher.acknowledge(info: 700, option: 1)
    expect(written).to eq([['PUT', 'DOP2/2/138',
                            dop2_leaf(2, 138, { 1 => dop2_field(:e16, 700), 5 => dop2_field(:e8, 1) }, idx2: 1)]])
  end

  context 'when it sleeps deeply' do
    let(:state) { { 'Status' => 4, 'RemoteEnable' => [15, 0, 1], 'StandbyState' => 2 } }

    it 'powers on as the app does: DeviceAction 2, then ApplianceState 4' do
      dishwasher.power_on
      expect(written.map { it[0..1] }).to eq([%w[PUT State], %w[PUT DOP2/2/1586]])
    end
  end

  context 'when it is on' do
    let(:state) { { 'Status' => 2, 'RemoteEnable' => [15, 0, 0], 'StandbyState' => 1 } }

    it 'powers off with ApplianceState 1' do
      dishwasher.power_off
      expect(written).to eq([['PUT', 'DOP2/2/1586', combi_state(0, 1, 0, 0)]])
    end
  end

  context 'without remote control' do
    let(:state) { { 'Status' => 2, 'RemoteEnable' => [0, 0, 0], 'StandbyState' => 1 } }

    it 'refuses to power off, as the app does' do
      expect { dishwasher.power_off }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end
end
