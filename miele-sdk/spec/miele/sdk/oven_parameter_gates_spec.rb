# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then [200, {}, served.fetch(path.delete_prefix("/Devices/#{fab}/"))]
      else [204, {}, '']
      end
    end
  end

  before do
    connect_to(fake)
    serve
    resources['DOP2/1/131?idx1=0&idx2=1'] = messages
  end

  after { fake.stop }

  def serve(status: 3, remote: [15, 0, 1], type: 5, parameters: {}, prog: 13)
    shown = { 1 => dop2_field(:e16, 0), 10 => dop2_field(:e8, type), 28 => dop2_field(:e16, prog) }
    resources['State'] = JSON.generate('Status' => status, 'RemoteEnable' => remote)
    resources['DOP2/1/1585'] = dop2_leaf(1, 1585, { 7 => dop2_field(:struct, shown) })
    resources['DOP2/1/1574?idx1=0&idx2=1'] =
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, shown_parameters(parameters)),
                           7 => dop2_field(:struct, shown) }, idx2: 1)
  end

  def messages(*ids)
    dop2_leaf(1, 131, { 2 => dop2_field(:struct_array, ids.map { { 1 => dop2_field(:e16, it) } }) }, idx2: 1)
  end

  def setters
    { target_temperature: [180, 6, :u16], core_target_temperature: [60, 7, :u16], moisture: [3, 2, :u8],
      grill_level: [2, 1, :u8], microwave_power: [0x10, 15, :u8], browning: [2, 30, :u8], doneness: [1, 31, :u8],
      duration: [1_800, 12, :u32], start_at: [:now, 13, :u64], end_at: [Time.at(1_700_003_600), 14, :u64] }
  end

  def written = fake.requests.select { it.verb == 'PUT' }.map { Miele::Sdk::Dop2.decode(it.body).fields[2].value }

  def ids(*names) = names.map { setters.fetch(it)[1] }

  def sent_unoffered(*names, shown: false)
    names.each do |name|
      expect([oven.parameter_shown?(name), oven.parameter_editable?(name)]).to eq([shown, false])
      set_parameter(oven, name, setters.fetch(name).first)
    end
  end

  def option(mask) = dop2_field(:struct, { 1 => dop2_field(:u8, mask), 2 => dop2_field(:bool, false) })

  it 'writes every parameter whose section the app shows, as it lets each change', :aggregate_failures do
    expect(setters.keys.map { [oven.parameter_shown?(it), oven.parameter_editable?(it)] }.uniq).to eq([[true, true]])
    expect([oven.option_shown?(:rapid_heating), oven.option_editable?(:rapid_heating)]).to eq([true, true])
    setters.each { |name, (value)| set_parameter(oven, name, value) }
    oven.set_options(rapid_heating: true)
    expect(written).to eq([6, 7, 2, 1, 15, 30, 31, 12, 13, 14, 21])
  end

  it 'writes every parameter while keeping warm or rapid cooling runs, which hides them but no option in the app',
     :aggregate_failures do
    [20, 19].each do |message|
      resources['DOP2/1/131?idx1=0&idx2=1'] = messages(message)
      sent_unoffered(*setters.keys)
      expect(oven.option_editable?(:rapid_heating)).to be(true)
    end
    expect(written).to eq(ids(*setters.keys) * 2)
  end

  it 'writes a parameter whose section the app removes while its value is not readable', :aggregate_failures do
    setters.each do |name, (_value, id, type)|
      current = type == :u8 ? 1 : 1_800
      serve(parameters: { id => shown_parameter(type, current, mask: 1) })
      sent_unoffered(name)
    end
    expect(written).to eq(ids(*setters.keys))
  end

  it 'sends and reads nothing for no option, even while the app hides the options', :aggregate_failures do
    serve(type: 1)
    expect { oven.set_options }.not_to raise_error
    expect(fake.requests.map(&:path)).not_to include(a_string_including('/DOP2/'))
  end

  it 'writes an option the oven does not make readable, which the app hides', :aggregate_failures do
    serve(parameters: { 27 => option(1) })
    expect([oven.option_shown?(:keep_warm), oven.option_editable?(:keep_warm)]).to eq([false, false])
    expect(oven.option_editable?(:rapid_heating)).to be(true)
    oven.set_options(keep_warm: true)
    expect(written).to eq([27])
  end

  it 'writes the duration and the start time while the oven runs with a duration set, which the app hides',
     :aggregate_failures do
    serve(status: 5)
    sent_unoffered(:duration, :start_at)
    expect(oven.parameter_editable?(:end_at)).to be(true)
    expect(written).to eq([12, 13])
  end

  it 'writes the start and end times while a readable duration is unset, which the app hides', :aggregate_failures do
    [0, 0xFFFF_FFFF].each do |unset|
      serve(parameters: { 12 => shown_parameter(:u32, unset) })
      sent_unoffered(:start_at, :end_at)
    end
    expect(oven.parameter_editable?(:duration)).to be(true)
    expect(written).to eq([13, 14] * 2)
  end

  it 'writes a target temperature while the current one is not above zero, which the app hides',
     :aggregate_failures do
    serve(parameters: { 6 => shown_parameter(:u16, 0), 7 => shown_parameter(:u16, 0) })
    sent_unoffered(:target_temperature)
    expect(oven.parameter_editable?(:core_target_temperature)).to be(true)
    expect(written).to eq([6])
  end

  it 'writes a parameter the oven does not make writable, which the app shows disabled', :aggregate_failures do
    setters.each do |name, (_value, id, type)|
      current = type == :u8 ? 1 : 1_800
      serve(parameters: { id => shown_parameter(type, current, mask: 8) })
      sent_unoffered(name, shown: true)
    end
    expect(written).to eq(ids(*setters.keys))
  end

  it 'writes an option the oven does not make writable, which the app shows disabled', :aggregate_failures do
    serve(parameters: { 27 => option(8) })
    expect([oven.option_shown?(:keep_warm), oven.option_editable?(:keep_warm)]).to eq([true, false])
    oven.set_options(keep_warm: true)
    expect(written).to eq([27])
  end

  it 'writes browning and doneness without mobile start, which the cooking level cells need', :aggregate_failures do
    serve(remote: [15, 0, 0])
    sent_unoffered(:browning, :doneness, shown: true)
    expect(oven.parameter_editable?(:moisture)).to be(true)
    expect(written).to eq([30, 31])
  end

  it 'sets the times of an own or automatic program without mobile start, which the app needs',
     :aggregate_failures do
    [2, 3, 4].each do |type|
      serve(type:, remote: [15, 0, 0])
      sent_unoffered(:duration, :start_at, :end_at, shown: true)
    end
    serve(type: 4)
    expect(oven.parameter_editable?(:duration)).to be(true)
    expect(written).to eq([12, 13, 14, 12, 12, 13, 14])
  end

  it 'writes the options of an automatic program without mobile start, which the app needs', :aggregate_failures do
    serve(type: 3, remote: [15, 0, 0])
    expect([oven.option_shown?(:keep_warm), oven.option_editable?(:keep_warm)]).to eq([true, false])
    oven.set_options(keep_warm: true)
    serve(type: 4, remote: [15, 0, 0])
    expect(oven.option_editable?(:keep_warm)).to be(true)
    expect(written).to eq([27])
  end

  it 'tells the app lets program 361 change only under mobile start, started or not', :aggregate_failures do
    serve(prog: 361, remote: [15, 0, 0])
    expect(oven.parameter_editable?(:moisture)).to be(false)
    serve(prog: 361)
    expect(oven.parameter_editable?(:moisture)).to be(true)
  end

  it 'tells the app lets no option change without remote control, though it shows it' do
    serve(remote: [0, 0, 0])
    expect([oven.option_shown?(:rapid_heating), oven.option_editable?(:rapid_heating)]).to eq([true, false])
  end

  it 'raises for a parameter the app has no section for' do
    expect { oven.parameter_shown?(:steam_bursts) }.to raise_error(KeyError)
  end
end
