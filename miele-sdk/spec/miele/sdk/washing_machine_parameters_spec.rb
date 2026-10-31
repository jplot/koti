# frozen_string_literal: true

RSpec.describe Miele::Sdk::WashingMachine do
  subject(:washer) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4) }
  let(:state) { { 'Status' => 3, 'RemoteEnable' => [15, 0, 1] } }
  let(:leaves) { {} }
  let(:fake) do
    current = state
    served = leaves
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/State\z} } then [200, {}, JSON.generate(current)]
      in { verb: 'GET', path: %r{/DOP2/2/1574} } then [200, {}, served.fetch(1574) { ps_context }]
      in { verb: 'GET', path: %r{/DOP2/2/1577} } then [200, {}, served.fetch(1577) { select }]
      in { verb: 'POST', body: /"82010100"/ } then [200, {}, JSON.generate(Response: "82011101#{active}")]
      in { verb: 'POST' } then [200, {}, '{"Response":"82011201"}']
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def struct(fields) = dop2_field(:struct, fields)

  def ps_context
    eco = struct({ 2 => dop2_field(:bool, true) })
    para = { 3 => struct({ 2 => dop2_field(:u8, 40), 3 => dop2_field(:u8, 0) }),
             5 => struct({ 2 => dop2_field(:u8, 120) }), 16 => struct({ 14 => eco }) }
    dop2_leaf(2, 1574, { 3 => struct(para), 6 => struct({ 1 => dop2_field(:e16, 28) }) }, idx2: 1)
  end

  def select(prog: 0, type: 0, **given)
    values = { temperature: 30, info: 0, spin: 100, eco: false, intensive: false }.merge(given)
    extras = { 14 => dop2_field(:bool, values[:eco]), 15 => dop2_field(:bool, values[:intensive]) }
    para = { 3 => dop2_field(:u8, values[:temperature]), 4 => dop2_field(:u8, values[:info]),
             5 => dop2_field(:u8, values[:spin]), 14 => struct(extras) }
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, prog), 3 => dop2_field(:e8, type), 6 => struct(para) })
  end

  def wm_context(para) = dop2_leaf(2, 1574, { 3 => struct(para), 6 => struct({ 1 => dop2_field(:e16, 28) }) }, idx2: 1)

  def wm_select(prog, type, para)
    dop2_leaf(2, 1577, { 1 => dop2_field(:e16, prog), 3 => dop2_field(:e8, type), 6 => struct(para) })
  end

  def active = %w[011c0000 28b00402 0000000000 00000000 00020000 e0000000].join

  def written = fake.requests.reject { it.verb == 'GET' }.map { [it.path.delete_prefix("/Devices/#{fab}/"), it.body] }

  it 'writes 2/1577 with the current values 2/1574 shows, then the parameters given, as the app does' do
    washer.set_parameters(temperature: 60, eco: true, extras: [:intensive])
    expect(written).to eq([['DOP2/2/1577', select(prog: 28, type: 2, temperature: 60, info: 1, spin: 120,
                                                  intensive: true)]])
  end

  it 'writes the spin speed in tens of rpm and keeps the current values otherwise' do
    washer.set_parameters(spin_speed: 1400)
    expect(written).to eq([['DOP2/2/1577', select(prog: 28, type: 2, temperature: 40, spin: 140, eco: true)]])
  end

  it 'writes temperature info 2 for a cold wash' do
    washer.set_parameters(temperature: 0)
    expect(written.last.last).to eq(select(prog: 28, type: 2, temperature: 0, info: 2, spin: 120, eco: true))
  end

  it 'writes the stains as flags, the drying level and the program mode, and the TwinDos containers' do
    para = { 13 => struct({ 1 => dop2_field(:u8_array, [0, 0]) }), 19 => dop2_field(:u32, 0),
             20 => dop2_field(:u16, 0), 21 => dop2_field(:u16, 0) }
    leaves[1577] = wm_select(0, 0, para)
    washer.set_parameters(stains: %i[blood tea], drying_level: :hand_iron, program_mode: 4, twin_dos: [1, 2])
    written_para = { 13 => struct({ 1 => dop2_field(:u8_array, [1, 2]) }), 19 => dop2_field(:u32, 0x100001),
                     20 => dop2_field(:u16, 4), 21 => dop2_field(:u16, 4) }
    expect(written.last.last).to eq(wm_select(28, 2, written_para))
  end

  it "copies each TwinDos container's current value 2/1574 shows" do
    containers = [{ 3 => dop2_field(:u8, 3) }, { 3 => dop2_field(:u8, 5) }]
    leaves[1574] = wm_context({ 15 => struct({ 1 => dop2_field(:struct_array, containers) }) })
    leaves[1577] = wm_select(0, 0, { 13 => struct({ 1 => dop2_field(:u8_array, [0, 0]) }), 19 => dop2_field(:u32, 0) })
    washer.set_parameters(stains: [])
    expected = wm_select(28, 2, { 13 => struct({ 1 => dop2_field(:u8_array, [3, 5]) }), 19 => dop2_field(:u32, 0) })
    expect(written.last.last).to eq(expected)
  end

  it 'leaves the drying time of a washer, which only a washer-dryer copies' do
    leaves[1574] = wm_context({ 22 => struct({ 6 => dop2_field(:u16, 120) }) })
    leaves[1577] = wm_select(0, 0, { 19 => dop2_field(:u32, 0), 22 => dop2_field(:u16, 0) })
    washer.set_parameters(stains: [])
    expect(written.last.last).to eq(wm_select(28, 2, { 19 => dop2_field(:u32, 0), 22 => dop2_field(:u16, 0) }))
  end

  context 'with a washer-dryer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 24, 'ProtocolVersion' => 4) }

    it 'copies the drying time 2/1574 shows' do
      leaves[1574] = wm_context({ 22 => struct({ 6 => dop2_field(:u16, 120) }) })
      leaves[1577] = wm_select(0, 0, { 19 => dop2_field(:u32, 0), 22 => dop2_field(:u16, 0) })
      washer.set_parameters(stains: [])
      expect(written.last.last).to eq(wm_select(28, 2, { 19 => dop2_field(:u32, 0), 22 => dop2_field(:u16, 120) }))
    end
  end

  it 'refuses extras or TwinDos containers 2/1577 does not carry, sending nothing', :aggregate_failures do
    leaves[1577] = wm_select(0, 0, { 19 => dop2_field(:u32, 0) })
    expect { washer.set_parameters(extras: [:eco]) }.to raise_error(ArgumentError)
    expect { washer.set_parameters(twin_dos: [1, 2]) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  it 'refuses a parameter or an extra the app does not write on this washer', :aggregate_failures do
    expect { washer.set_parameters(master_care: 1) }.to raise_error(ArgumentError)
    expect { washer.set_parameters(extras: [:short]) }.to raise_error(ArgumentError)
    expect(written).to be_empty
  end

  context 'when its program runs' do
    let(:state) { { 'Status' => 5, 'RemoteEnable' => [15, 0, 1] } }

    it 'refuses to set parameters, as the app does' do
      expect { washer.set_parameters(spin_speed: 1400) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'with a Dop1 washer' do
    let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 2) }

    it 'copies the active parameters of 8201, then writes the parameters given, the reserve bits cleared' do
      washer.set_parameters(temperature: 60, eco: true, extras: [:eco], stains: [:urine])
      expect(written.map { JSON.parse(it.last).fetch('Request') })
        .to eq(%w[82010100 82010100011c00003bb004020000000000000000000012000010000000])
    end

    it 'writes both TwinDos containers only when given both', :aggregate_failures do
      washer.set_parameters(twin_dos: [1, 2])
      washer.set_parameters(twin_dos: [1])
      requests = written.map { JSON.parse(it.last).fetch('Request') }.reject { it == '82010100' }
      expect(requests.map { it[24, 4] }).to eq(%w[0102 0000])
    end

    it 'writes 0 for a temperature the app has no code for', :aggregate_failures do
      washer.set_parameters(temperature: 30, eco: true)
      washer.set_parameters(temperature: 33)
      requests = written.map { JSON.parse(it.last).fetch('Request') }.reject { it == '82010100' }
      expect(requests.map { it[16, 2] }).to eq(%w[00 00])
    end
  end
end
