# frozen_string_literal: true

RSpec.describe Miele::Sdk::WashingMachine do
  subject(:washer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4) }
  let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'StartTime' => [0, 0] } }
  let(:shown) { { requests: [1, 2], supported: 3, current: 0 } }
  let(:fake) do
    current = state
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(current)]
      in { verb: 'GET', path: %r{/DOP2/2/(\d+)} } then [200, {}, leaf(Regexp.last_match(1).to_i)]
      in { verb: 'POST', body: /"82010100"/ } then [200, {}, JSON.generate(Response: "82011101#{'00' * 25}")]
      in { verb: 'POST' } then [200, {}, '{"Response":"82011201"}']
      else [204, {}, '']
      end
    end
  end

  before do
    allow(Time).to receive(:now).and_return(Time.new(2026, 10, 31, 20, 0, 0))
    connect_to(fake)
  end

  after { fake.stop }

  def struct(fields) = dop2_field(:struct, fields)

  def leaf(attribute)
    case attribute
    when 1585 then dop2_leaf(2, 1585, { 6 => struct({ 1 => dop2_field(:e8, 3) }),
                                        9 => dop2_field(:e16_array, shown[:requests]) })
    when 1583 then dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 0) })
    when 1574 then ps_context
    when 1577 then select(0, 0, 0, 0)
    end
  end

  def ps_context
    mode = struct({ 2 => dop2_field(:u8, shown[:supported]), 3 => dop2_field(:u8, shown[:current]) })
    dop2_leaf(2, 1574, { 3 => struct({ 2 => mode }), 6 => struct({ 1 => dop2_field(:e16, 28) }) }, idx2: 1)
  end

  def select(prog, type, start, mode)
    para = { 1 => dop2_field(:u64, start), 2 => dop2_field(:u8, mode) }
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, prog), 3 => dop2_field(:e8, type), 6 => struct(para) })
  end

  def written = fake.requests.reject { it.verb == 'GET' }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body] }

  def json_written = written.map { |path, body| [path, JSON.parse(body)] }

  it 'counts down in minutes from a minute ago, as the app does, then sends request 8' do
    washer.start_delayed(Time.new(2026, 10, 31, 21, 30))
    expect(written).to eq([['DOP2/2/1577', select(28, 2, 91, 1)],
                           ['DOP2/2/1583', dop2_leaf(2, 1583, { 1 => dop2_field(:e16, 8) })]])
  end

  context 'when the washer counts only to a time' do
    let(:shown) { { requests: [1, 2], supported: 8, current: 0 } }

    it 'sets the next such time as local seconds since 1970' do
      washer.start_delayed(Time.new(2026, 10, 31, 6, 15))
      target = Time.new(2026, 11, 1, 6, 15)
      expect(written.first).to eq(['DOP2/2/1577', select(28, 2, target.to_i + target.utc_offset, 8)])
    end
  end

  context 'when the washer counts down only with a smart start' do
    let(:shown) { { requests: [1, 2], supported: 32 | 2, current: 0 } }

    it 'prefers mode 32, in minutes, to mode 2' do
      washer.start_delayed(Time.new(2026, 10, 31, 21, 30))
      expect(written.first).to eq(['DOP2/2/1577', select(28, 2, 91, 32)])
    end
  end

  context 'when the washer shows no start mode the app sets' do
    let(:shown) { { requests: [1, 2], supported: 4, current: 0 } }

    it 'writes the selection as copied, then sends request 8' do
      washer.start_delayed(Time.new(2026, 10, 31, 21, 30))
      expect(written.first).to eq(['DOP2/2/1577', select(28, 2, 0, 0)])
    end
  end

  context 'when its program runs' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1] } }
    let(:shown) { { requests: [2, 3], supported: 3, current: 0 } }

    it 'refuses a delayed start, as the app offers neither start nor request 8' do
      expect { washer.start_delayed(Time.new(2026, 10, 31, 21, 30)) }
        .to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with a Dop1 washer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 2) }

    it 'resets StartTime, sets it in hours and minutes, writes 8201 back and starts' do
      washer.start_delayed(Time.new(2026, 10, 31, 21, 30))
      expect(json_written).to eq([['State', { 'StartTime' => [0, 0] }], ['State', { 'StartTime' => [1, 31] }],
                                  ['DOP/', { 'Request' => '82010100' }],
                                  ['DOP/', { 'Request' => "82010100#{'00' * 25}" }],
                                  ['State', { 'ProcessAction' => 1 }]])
    end
  end

  context 'with a Dop1 washer that has a start time' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 2) }
    let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1], 'SignalDoor' => false, 'StartTime' => [1, 0] } }

    it 'sets the new start time without resetting it first' do
      washer.start_delayed(Time.new(2026, 10, 31, 21, 30))
      expect(json_written.first).to eq(['State', { 'StartTime' => [1, 31] }])
    end
  end
end
