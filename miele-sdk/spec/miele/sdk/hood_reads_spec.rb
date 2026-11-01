# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hood do
  subject(:hood) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:protocol) { 2 }
  let(:ident) do
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => protocol,
                                                  'DeviceIdentLabel' => { 'TechType' => 'DA2698' })
  end
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then served.fetch(path.delete_prefix("/Devices/#{fab}/")) { [404, {}, ''] }
      in { verb: 'POST' } then served.fetch('DOP')
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def serve(bytes = {}, size = 73, json = {})
    data = Array.new(size, 0)
    bytes.each { |index, value| Array(value).each_with_index { |byte, offset| data[index + offset] = byte } }
    extended = bytes.empty? ? '' : data.pack('C*').unpack1('H*').upcase
    resources['State'] = [200, {}, JSON.generate({ 'Status' => 4, 'ExtendedState' => extended }.merge(json))]
  end

  def light(**values)
    described_class::Light.new(exists: false, dimmable: false, rgb: false, temperature_settable: false, dimmer: 0,
                               temperature: 0).with(**values)
  end

  it 'reads the fan level at byte 3' do
    serve(3 => 2)
    expect(hood.fan_level).to eq(2)
  end

  it "reads the filters' hours and thresholds as u16 MSB" do
    serve(16 => [0x00, 0xC8], 18 => [0x00, 0x32], 20 => [0x01, 0x2C], 22 => [0x00, 0x0A], 30 => 0b0010)
    expect([hood.grease_filter, hood.charcoal_filter])
      .to eq([described_class::Filter.new(threshold: 200, hours: 50, reached: true),
              described_class::Filter.new(threshold: 300, hours: 10, reached: false)])
  end

  it 'reads nil when ExtendedState is empty' do
    serve
    expect([hood.fan_level, hood.grease_filter, hood.run_on, hood.lights]).to all(be_nil)
  end

  it 'reads the run-on setting as the app rounds it, and the minutes left', :aggregate_failures do
    serve(25 => 3, 28 => 4)
    expect(hood.run_on).to eq(described_class::RunOn.new(setting: 15, minutes_left: 3))
    serve(25 => 2, 28 => 2)
    expect(hood.run_on.setting).to eq(5)
    serve(28 => 9)
    expect(hood.run_on).to eq(described_class::RunOn.new(setting: 0, minutes_left: 0))
  end

  it 'reads what the fan and the main light support', :aggregate_failures do
    serve(30 => 0b1000, 34 => [0b0000_1000, 0b0001_0010], 37 => [0x00, 0b1000_0000], 8 => [0x80, 0x00],
          10 => [0x0F, 0xA0])
    resources['DOP'] = [200, {}, '{"Response":"12011100009C5C00000000"}']
    expect([hood.fan_settable?, hood.booster_2_available?]).to eq([true, true])
    expect(hood.lights.main)
      .to eq(light(exists: true, dimmable: true, temperature_settable: true, dimmer: 0x8000, temperature: 4000))
  end

  it "takes a Dop hood's ambient light to exist only with an RGB panel, as setting 40028 tells" do
    serve(34 => [0x01, 0x04], 12 => [0x40, 0x00])
    resources['DOP'] = [200, {}, '{"Response":"12011100009C5C00000007"}']
    expect(hood.lights.ambient).to eq(light(exists: true, rgb: true, dimmer: 0x4000))
  end

  it 'reads height, dehumidification and grease melting', :aggregate_failures do
    serve(36 => 2, 37 => [0b0000_0010, 0b0000_1000], 39 => 2, 40 => 3, 67 => 40, 68 => 12, 69 => 30)
    expect(hood.height_position).to eq(2)
    expect(hood.dehumidification)
      .to eq(described_class::Dehumidification.new(supported: true, mode: :regulated, state: :pending))
    expect(hood.grease_melting)
      .to eq(described_class::GreaseMelting.new(supported: true, minutes_left: 30, threshold: 40, hours: 12))
  end

  it 'reads auto refresh as supported unless the model is one the app excludes', :aggregate_failures do
    serve(34 => [0x00, 0x01])
    expect(hood.auto_refresh_supported?).to be(true)
    label = ident.device_ident_label.with(tech_type: 'DAS 2620')
    excluded = described_class.new('127.0.0.1', ident: ident.with(device_ident_label: label))
    expect(excluded.auto_refresh_supported?).to be(false)
  end

  it 'reads ColorFlow, raising a local 404, which a module that does not serve it answers too', :aggregate_failures do
    expect { hood.color_flow }.to raise_error(Miele::Sdk::NotFoundError)
    resources['ColorFlow'] = [200, {}, '{"active":true,"intervalDurationSeconds":20}']
    expect(hood.color_flow).to eq(described_class::ColorFlow.new(active: true, interval: 20))
  end

  it 'reads a 404 through the cloud as no ColorFlow, as the app does' do
    cloud = instance_double(Miele::Sdk::Cloud::Channel)
    allow(cloud).to receive(:request).and_raise(Miele::Sdk::NotFoundError.new(404))
    expect(described_class.new('127.0.0.1', ident:, fab:, cloud:).color_flow).to be_nil
  end

  it 'reads an interval the app does not know as 10 seconds, as its mapper does' do
    resources['ColorFlow'] = [200, {}, '{"active":true,"intervalDurationSeconds":15}']
    expect(hood.color_flow.interval).to eq(10)
  end

  context 'with a DOP2 hood' do
    let(:protocol) { 4 }

    it 'reads a 500 on ColorFlow as having none, as the app does for DOP2' do
      resources['ColorFlow'] = [500, {}, '']
      expect(hood.color_flow).to be_nil
    end

    it 'reads its values little-endian, and its ambient light from bits 2 and 8', :aggregate_failures do
      serve(16 => [0xC8, 0x00], 34 => [0x04, 0x01], 12 => [0x00, 0x40])
      expect(hood.grease_filter.threshold).to eq(200)
      expect(hood.lights.ambient).to eq(light(exists: true, rgb: true, dimmer: 0x4000))
    end
  end

  context 'with an Opcode hood' do
    let(:protocol) { 1 }

    it 'reads the fan and the light from State, the rest from its own ExtendedState', :aggregate_failures do
      serve({ 13 => 5, 15 => 20, 16 => 25, 25 => 0b1000 }, 32, { 'VentilationStep' => 2, 'Light' => 1 })
      expect([hood.fan_level, hood.fan_settable?, hood.run_on]).to eq([2, true, described_class::RunOn.new(5, 5)])
      expect(hood.grease_filter).to eq(described_class::Filter.new(threshold: 20, hours: 25, reached: true))
      expect(hood.lights).to eq(described_class::Lights.new(main: light(exists: true, dimmer: 65_535),
                                                            ambient: light))
    end
  end
end
