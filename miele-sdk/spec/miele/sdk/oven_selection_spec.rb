# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { naps << seconds }, clock:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:naps) { [] }
  let(:resources) { { put: [] } }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then answer(served.fetch(path.delete_prefix("/Devices/#{fab}/")))
      else served[:put].shift || [204, {}, '']
      end
    end
  end

  before do
    connect_to(fake)
    state
    device
    program_context(13)
    queries
  end

  after { fake.stop }

  def clock = -> { naps.sum + (fake.requests.size * round_trip) }

  def round_trip = 0

  def answer(bodies)
    body = bodies.size > 1 ? bodies.shift : bodies.first
    body.is_a?(Array) ? body : [200, {}, body]
  end

  def written = fake.requests.select { it.verb == 'PUT' }.map { it.body.unpack1('H*') }

  def state(status: 2, remote: [15, 0, 0])
    resources['State'] = [JSON.generate('Status' => status, 'RemoteEnable' => remote)]
  end

  def device(prog_id: 0)
    resources['DOP2/1/1585'] = [dop2_leaf(1, 1585, { 7 => dop2_field(:struct, { 28 => dop2_field(:e16, prog_id) }) })]
  end

  def program_context(*prog_ids, parameters: {})
    resources['DOP2/1/1574?idx1=0&idx2=1'] = prog_ids.map do |prog_id|
      attributes = { 28 => dop2_field(:e16, prog_id) }
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, oven_parameters(parameters)),
                           7 => dop2_field(:struct, attributes) }, idx2: 1)
    end
  end

  def queries(*ids)
    shown = ids.map { { 1 => dop2_field(:e16, it) } }
    resources['DOP2/1/131?idx1=0&idx2=1'] = [dop2_leaf(1, 131, { 4 => dop2_field(:struct_array, shown) }, idx2: 1)]
  end

  def required(type, current) = dop2_field(:struct, { 1 => dop2_field(:u8, 2), 4 => dop2_field(type, current) })

  def parameter(id, type, value)
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, 13), 3 => dop2_field(:e8, 2), 2 => dop2_field(:u16, id),
                         7 => dop2_field(:struct, { id => dop2_field(type, value) }) }).unpack1('H*')
  end

  def selected = '001300020629000000000002000107000d00030400'

  def expect_selected_unoffered
    expect(oven.select_program_offered?).to be(false)
    oven.select_program(13)
  end

  it 'selects a program with selection type 0', :aggregate_failures do
    expect(oven.select_program_offered?).to be(true)
    oven.select_program(13)
    expect(written).to eq([selected])
  end

  it 'selects while the oven asks a question the app supports' do
    queries(4)
    oven.select_program(13)
    expect(written).to eq(['001300020629000000000002000107000d00030400'])
  end

  it 'selects while the oven shows a program on 1/1585, which the app does not offer', :aggregate_failures do
    device(prog_id: 13)
    expect_selected_unoffered
    expect(written).to eq([selected])
  end

  it 'selects while 1/1585 shows no ProgId, the app then having no selection to offer', :aggregate_failures do
    resources['DOP2/1/1585'] = [dop2_leaf(1, 1585, {})]
    expect_selected_unoffered
    expect(written).to eq([selected])
  end

  it 'selects while the oven asks query 16011 or 16013, which the app does not offer', :aggregate_failures do
    [16_011, 16_013].each do |id|
      queries(id)
      expect_selected_unoffered
    end
    expect(written).to eq([selected] * 2)
  end

  it 'selects on an oven off, not connected, running or waiting to start, which the app does not offer',
     :aggregate_failures do
    [1, 255, 5, 4].each do |status|
      state(status:)
      expect_selected_unoffered
    end
    expect(written).to eq([selected] * 4)
  end

  it 'selects without remote control, or under local control, which the app does not offer', :aggregate_failures do
    [[0, 0, 1], [7, 0, 0]].each do |remote|
      state(remote:)
      expect_selected_unoffered
    end
    expect(written).to eq([selected] * 2)
  end

  it 'polls 1/1574 every 3 s until it shows the program, then writes the required parameters', :aggregate_failures do
    program_context(0, 0, 13, parameters: { 6 => required(:u16, 3_730) })
    oven.select_program(13)
    expect(naps).to eq([3, 3])
    expect(written).to eq(['001300020629000000000002000107000d00030400', parameter(6, :u16, 3_729)])
  end

  it 'reads 1/1574 again 1.5 s after a 500, as the app retries, then writes the parameters', :aggregate_failures do
    program_context(13, parameters: { 6 => required(:u16, 18_000) })
    resources['DOP2/1/1574?idx1=0&idx2=1'].unshift([500, {}, ''])
    oven.select_program(13)
    expect(naps).to eq([1.5])
    expect(written).to eq(['001300020629000000000002000107000d00030400', parameter(6, :u16, 18_000)])
  end

  it "retries refused reads 1.5^n s apart until the app's 15 s are up", :aggregate_failures do
    resources['DOP2/1/1574?idx1=0&idx2=1'] = [[503, {}, '']]
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError)
    expect(naps).to eq([1.5, 2.25, 3.375, 5.0625])
  end

  it 'ends the wait on a read refused with a 4xx, which the app does not retry' do
    resources['DOP2/1/1574?idx1=0&idx2=1'] = [[404, {}, '']]
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::NotFoundError)
  end

  it 'gives up after 15 s when 1/1574 never shows the program, writing no parameter', :aggregate_failures do
    program_context(0, parameters: { 6 => required(:u16, 18_000) })
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError)
    expect(naps).to eq([3, 3, 3, 3])
    expect(written).to eq(['001300020629000000000002000107000d00030400'])
  end

  context 'when each round trip takes half a second' do
    def round_trip = 0.5

    it 'counts the 15 s from before the write, which leave room for three waits only', :aggregate_failures do
      program_context(0)
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError, /did not show program 13/)
      expect(naps).to eq([3, 3, 3])
    end
  end

  context 'when each round trip takes a second' do
    def round_trip = 1

    it 'counts them in the 15 s, which then leave room for four reads of 1/1574', :aggregate_failures do
      program_context(0, parameters: { 6 => required(:u16, 18_000) })
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError)
      expect(naps).to eq([3, 3, 3])
    end

    it 'gives each request only what the 15 s have left, from before the write', :aggregate_failures do
      Miele::Sdk.config.read_timeout = 30
      timeouts = read_timeouts
      program_context(0)
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError)
      expect(timeouts).to eq([15, 14, 13, 9, 5, 1])
    end
  end

  it 'writes the required parameters after the 15 s, with no bound of their own' do
    Miele::Sdk.config.read_timeout = 30
    program_context(13, parameters: { 6 => required(:u16, 18_000) })
    oven.fab
    timeouts = read_timeouts
    oven.select_program(13)
    expect(timeouts).to eq([15, 15, 30])
  end

  it 'writes every required parameter though one is refused, keeps the selection and raises it',
     :aggregate_failures do
    program_context(13, parameters: { 6 => required(:u16, 18_000), 7 => required(:u16, 6_000) })
    resources[:put] = [[204, {}, ''], [500, {}, '']]
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ResponseError)
    expect(written.drop(1)).to eq([parameter(6, :u16, 18_000), parameter(7, :u16, 6_000)])
  end

  it 'writes no required parameter while 1/1574 lacks one of the eight, keeps the selection and raises',
     :aggregate_failures do
    program_context(13, parameters: { 6 => required(:u16, 18_000), 15 => nil })
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError)
    expect(written).to eq(['001300020629000000000002000107000d00030400'])
  end
end
