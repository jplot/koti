# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { naps << seconds }) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:naps) { [] }
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, answer(served.fetch(path.delete_prefix("/Devices/#{fab}/")))]
      else [204, {}, '']
      end
    end
  end

  before do
    connect_to(fake)
    state
    messages
    levels(31 => level(2, mask: 3))
  end

  after { fake.stop }

  def answer(bodies) = bodies.size > 1 ? bodies.shift : bodies.first

  def state(status: 7, remote: [15, 0, 1])
    resources['State'] = [JSON.generate('Status' => status, 'RemoteEnable' => remote)]
  end

  def messages(*ids)
    shown = ids.map { { 1 => dop2_field(:e16, it) } }
    resources['DOP2/1/131?idx1=0&idx2=1'] = [dop2_leaf(1, 131, { 2 => dop2_field(:struct_array, shown) }, idx2: 1)]
  end

  def phases(*values, type: 5)
    resources['DOP2/1/1585'] = [0, *values].map do |phase|
      shown = { 1 => phase&.then { dop2_field(:e16, it) }, 10 => dop2_field(:e8, type), 16 => dop2_field(:e8, 1),
                28 => dop2_field(:e16, 13) }
      dop2_leaf(1, 1585, { 7 => dop2_field(:struct, shown.compact) })
    end
  end

  def levels(*parameters)
    resources['DOP2/1/1574?idx1=0&idx2=1'] = parameters.map do |shown|
      values = { 30 => level(4, mask: 1), 31 => level(2, mask: 1) }.merge(shown).compact
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, values),
                           7 => dop2_field(:struct, { 28 => dop2_field(:e16, 13) }) }, idx2: 1)
    end
  end

  def level(current, mask:) = dop2_field(:struct, { 1 => dop2_field(:u8, mask), 4 => dop2_field(:u8, current) })

  def written = fake.requests.select { it.verb == 'PUT' }.map { it.body.unpack1('H*') }

  def expect_refused(reason)
    expect { oven.continue_cooking }.to raise_error(Miele::Sdk::ActionUnavailableError, reason)
    expect(written).to be_empty
  end

  def user_request(id) = dop2_leaf(2, 1583, { 1 => dop2_field(:e16, id) }).unpack1('H*')

  def parameter(id, value)
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 13), 3 => dop2_field(:e8, 2), 2 => dop2_field(:u16, id),
                         7 => dop2_field(:struct, { id => dop2_field(:u8, value) }) }).unpack1('H*')
  end

  it 'refuses a program that is not finished, as the app shows no continue bubble then', :aggregate_failures do
    phases(28_100)
    state(status: 5)
    expect_refused(/finished/)
  end

  it 'refuses a cleaning or maintenance program, which the app never offers to continue', :aggregate_failures do
    phases(28_100, type: 7)
    expect_refused(/finished/)
  end

  it 'refuses while keeping warm or rapid cooling runs after the end', :aggregate_failures do
    phases(28_100)
    [20, 19].each do |id|
      messages(id)
      expect { oven.continue_cooking }.to raise_error(Miele::Sdk::ActionUnavailableError, /after the end/)
    end
    expect(written).to be_empty
  end

  it 'refuses without mobile start, as the app keeps its continue button disabled', :aggregate_failures do
    phases(28_100)
    state(remote: [15, 0, 0])
    expect_refused(/mobile start/)
  end

  it 'refuses under local control', :aggregate_failures do
    phases(28_100)
    state(remote: [7, 0, 1])
    expect_refused(/mobile start/)
  end

  it 'refuses without remote control', :aggregate_failures do
    phases(28_100)
    state(remote: [0, 0, 1])
    expect_refused(/mobile start/)
  end

  it 'raises the doneness the oven asks for by one step, then sees it cook on' do
    phases(10_000, 28_100)
    oven.continue_cooking
    expect(written).to eq([user_request(72), parameter(31, 3)])
  end

  it 'raises the browning when the oven does not ask for the doneness' do
    phases(10_000, 28_114)
    levels(30 => level(4, mask: 3))
    oven.continue_cooking
    expect(written).to eq([user_request(72), parameter(30, 5)])
  end

  it 'reads 1/1585 and 1/1574 every 3 s until the oven asks, then until it cooks on', :aggregate_failures do
    phases(0, 10_000, 0, 28_124)
    levels({}, 31 => level(2, mask: 3))
    oven.continue_cooking
    expect(naps).to eq([3, 3, 3])
    expect(written).to eq([user_request(72), parameter(31, 3)])
  end

  it 'writes no level when the oven cooks on by itself' do
    phases(28_115)
    oven.continue_cooking
    expect(written).to eq([user_request(72)])
  end

  it 'writes the step past 255 as 0, as the app converts it to a byte' do
    phases(10_000, 28_100)
    levels(31 => level(255, mask: 3))
    oven.continue_cooking
    expect(written.last).to eq(parameter(31, 0))
  end

  it 'gives up within the 15 s the app waits when the oven does not cook on', :aggregate_failures do
    phases(10_000, 0)
    expect { oven.continue_cooking }.to raise_error(Miele::Sdk::ActionFailedError)
    expect(naps.sum).to be < 15
    expect(written).to eq([user_request(72), parameter(31, 3)])
  end

  it 'fails at once when 1/1585 shows no program phase, as the app reads it with LeftOrThrow', :aggregate_failures do
    phases(nil)
    expect { oven.continue_cooking }.to raise_error(Miele::Sdk::ActionFailedError, /phase/)
    expect(naps).to be_empty
  end

  it 'fails when 1/1574 shows no ProgId for the level it writes' do
    phases(10_000, 28_100)
    resources['DOP2/1/1574?idx1=0&idx2=1'] =
      [dop2_leaf(1, 1574, { 4 => dop2_field(:struct, { 30 => level(4, mask: 1), 31 => level(2, mask: 3) }) }, idx2: 1)]
    expect { oven.continue_cooking }.to raise_error(Miele::Sdk::ActionFailedError, /ProgId/)
  end

  it 'fails when 1/1574 has no doneness, as the app reads it first' do
    phases(10_000, 28_100)
    levels(31 => nil)
    expect { oven.continue_cooking }.to raise_error(Miele::Sdk::ActionFailedError, /doneness/)
  end
end
