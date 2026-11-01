# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { naps << seconds }) }

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

  def answer(bodies) = [200, {}, bodies.size > 1 ? bodies.shift : bodies.first]

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
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, parameters), 7 => dop2_field(:struct, attributes) }, idx2: 1)
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

  it 'selects a program with selection type 0' do
    oven.select_program(13)
    expect(written).to eq(['001300020629000000000002000107000d00030400'])
  end

  it 'selects while the oven asks a question the app supports' do
    queries(4)
    oven.select_program(13)
    expect(written).to eq(['001300020629000000000002000107000d00030400'])
  end

  it 'refuses while the oven shows a program on 1/1585, as the app does', :aggregate_failures do
    device(prog_id: 13)
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionUnavailableError, /shows a program/)
    expect(written).to be_empty
  end

  it 'refuses while 1/1585 shows no ProgId, the app then having no selection to offer' do
    resources['DOP2/1/1585'] = [dop2_leaf(1, 1585, {})]
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionUnavailableError, /shows a program/)
  end

  it 'refuses while the oven asks query 16011 or 16013', :aggregate_failures do
    [16_011, 16_013].each do |id|
      queries(id)
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionUnavailableError, /question/)
    end
    expect(written).to be_empty
  end

  it 'refuses an oven off, not connected, running or waiting to start', :aggregate_failures do
    [1, 255, 5, 4].each do |status|
      state(status:)
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionUnavailableError, /off|runs/)
    end
    expect(written).to be_empty
  end

  it 'refuses without remote control, or under local control', :aggregate_failures do
    [[0, 0, 1], [7, 0, 0]].each do |remote|
      state(remote:)
      expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionUnavailableError, /remote control/)
    end
    expect(written).to be_empty
  end

  it 'polls 1/1574 every 3 s until it shows the program, then writes the required parameters', :aggregate_failures do
    program_context(0, 0, 13, parameters: { 6 => required(:u16, 3_730) })
    oven.select_program(13)
    expect(naps).to eq([3, 3])
    expect(written).to eq(['001300020629000000000002000107000d00030400', parameter(6, :u16, 3_729)])
  end

  it 'gives up after 15 s when 1/1574 never shows the program, writing no parameter', :aggregate_failures do
    program_context(0, parameters: { 6 => required(:u16, 18_000) })
    expect { oven.select_program(13) }.to raise_error(Miele::Sdk::ActionFailedError)
    expect(naps).to eq([3, 3, 3, 3])
    expect(written).to eq(['001300020629000000000002000107000d00030400'])
  end

  it 'keeps the selection when a required parameter is refused, as the app does', :aggregate_failures do
    program_context(13, parameters: { 6 => required(:u16, 18_000) })
    resources[:put] = [[204, {}, ''], [500, {}, '']]
    expect { oven.select_program(13) }.not_to raise_error
    expect(written.size).to eq(2)
  end
end
