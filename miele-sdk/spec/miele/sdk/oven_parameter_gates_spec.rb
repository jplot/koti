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
  end

  after { fake.stop }

  def serve(status: 3, remote: [15, 0, 1], type: 5, parameters: {})
    shown = { 10 => dop2_field(:e8, type), 28 => dop2_field(:e16, 13) }
    resources['State'] = JSON.generate('Status' => status, 'RemoteEnable' => remote)
    resources['DOP2/1/1585'] = dop2_leaf(1, 1585, { 7 => dop2_field(:struct, shown) })
    resources['DOP2/1/1574?idx1=0&idx2=1'] =
      dop2_leaf(1, 1574, { 4 => dop2_field(:struct, shown_parameters(parameters)),
                           7 => dop2_field(:struct, { 28 => dop2_field(:e16, 13) }) }, idx2: 1)
  end

  def setters
    { target_temperature: [180, 6, :u16], core_target_temperature: [60, 7, :u16], moisture: [3, 2, :u8],
      grill_level: [2, 1, :u8], microwave_power: [0x10, 15, :u8], browning: [2, 30, :u8], doneness: [1, 31, :u8],
      steam_bursts: [2, 18, :u8], duration: [1_800, 12, :u32], start_at: [:now, 13, :u64],
      end_at: [Time.at(1_700_003_600), 14, :u64] }
  end

  def written = fake.requests.select { it.verb == 'PUT' }.map { Miele::Sdk::Dop2.decode(it.body).fields[2].value }

  def refused(*names, error: /hides/)
    names.each do |name|
      expect { oven.public_send(:"#{name}=", setters.fetch(name).first) }.to raise_error(error)
    end
  end

  it 'writes every parameter whose section the app shows' do
    setters.each { |name, (value)| oven.public_send(:"#{name}=", value) }
    oven.set_options(rapid_heating: true)
    expect(written).to eq([6, 7, 2, 1, 15, 30, 31, 18, 12, 13, 14, 21])
  end

  it 'refuses a parameter whose section the app removes while its value is not readable', :aggregate_failures do
    setters.each do |name, (_value, id, type)|
      current = type == :u8 ? 1 : 1_800
      serve(parameters: { id => shown_parameter(type, current, mask: 1) })
      refused(name)
    end
    expect(written).to be_empty
  end

  it 'refuses an option the oven does not make readable, and writes the others', :aggregate_failures do
    serve(parameters: { 27 => dop2_field(:struct, { 1 => dop2_field(:u8, 1), 2 => dop2_field(:bool, false) }) })
    expect { oven.set_options(keep_warm: true) }.to raise_error(Miele::Sdk::ActionUnavailableError, /hides/)
    oven.set_options(rapid_heating: true)
    expect(written).to eq([21])
  end

  it 'refuses the duration and the start time while the oven runs with a duration set', :aggregate_failures do
    serve(status: 5)
    refused(:duration, :start_at)
    oven.end_at = Time.at(1_700_003_600)
    expect(written).to eq([14])
  end

  it 'refuses the start and end times while a readable duration is unset', :aggregate_failures do
    [0, 0xFFFF_FFFF].each do |unset|
      serve(parameters: { 12 => shown_parameter(:u32, unset) })
      refused(:start_at, :end_at)
    end
    oven.duration = 1_800
    expect(written).to eq([12])
  end

  it 'refuses steam bursts whose type the app shows no cell for', :aggregate_failures do
    [0, 8].each do |count|
      serve(parameters: { 18 => shown_parameter(:u8, count) })
      refused(:steam_bursts)
    end
    expect(written).to be_empty
  end
end
