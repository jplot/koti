# frozen_string_literal: true

RSpec.describe Miele::Sdk::Dishwasher do
  subject(:dishwasher) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:protocol) { 2 }
  let(:ident) do
    Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 7, 'ProtocolVersion' => protocol,
                                                  'DeviceIdentLabel' => { 'TechType' => 'G7310' })
  end
  let(:resources) { {} }
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then served.fetch(path.delete_prefix("/Devices/#{fab}/")) { [404, {}, ''] }
      in { verb: 'POST' } then [200, {}, '{"Response":"89051100010203"}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def state(json) = resources['State'] = [200, {}, JSON.generate(json)]

  it 'reads the supported requests of a Dop1 dishwasher from its Status', :aggregate_failures do
    { 3 => %i[start], 4 => %i[start cancel], 5 => %i[pause stop], 2 => %i[start stop] }.each do |status, requests|
      state('Status' => status)
      expect(dishwasher.supported_requests).to eq(requests)
    end
  end

  it 'reads the energy and water a Dop1 dishwasher uses now, as the app does' do
    bytes = Array.new(19, 0)
    bytes[15, 4] = [0x00, 0x7B, 0x01, 0xC8]
    state('Status' => 5, 'ExtendedState' => bytes.pack('C*').unpack1('H*'))
    expect(dishwasher.consumption).to eq(described_class::Consumption.new(energy: 12.3, water: 45.6))
  end

  it 'reads the program list of a Dop1 dishwasher from 8905', :aggregate_failures do
    expect(dishwasher.program_list).to be_a(Miele::Sdk::Objects::Dishwasher::SmartControlGsdProgrammliste)
    expect(JSON.parse(fake.requests.last.body)).to eq('Request' => '89050100')
  end

  it 'reads the selection of a Dop1 dishwasher from 8907, and its consumables as served', :aggregate_failures do
    resources['Consumables'] = [200, {}, '{"trays":[]}']
    expect(dishwasher.selection).to be_a(Miele::Sdk::Objects::Dishwasher::SmartControlGsdProgrammwahlLesen)
    expect(JSON.parse(fake.requests.last.body)).to eq('Request' => '89070100')
    expect(dishwasher.consumables).to eq('trays' => [])
  end

  it 'locks only a DOP2 dishwasher' do
    state('Status' => 4, 'RemoteEnable' => [7, 0, 0])
    expect(dishwasher.locked?).to be(false)
  end

  context 'with a PG81 dishwasher' do
    let(:ident) do
      Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 8, 'ProtocolVersion' => 2,
                                                    'DeviceIdentLabel' => { 'TechType' => 'PG8133' })
    end

    it 'offers no request, as the app does', :aggregate_failures do
      state('Status' => 4, 'ExtendedState' => '00' * 19)
      expect([dishwasher.supported_requests, dishwasher.consumption]).to eq([[], nil])
    end
  end

  context 'with a DOP2 dishwasher' do
    let(:protocol) { 4 }

    it 'reads the supported requests from 2/1585, as the app names them' do
      resources['DOP2/2/1585?idx1=0&idx2=1'] =
        [200, {}, dop2_leaf(2, 1585, { 9 => dop2_field(:e16_array, [1, 8, 52, 99]) }, idx2: 1)]
      expect(dishwasher.supported_requests).to eq(%i[start start_delay cancel])
    end

    it 'reads a setting at idx1 = its id' do
      resources['DOP2/2/105?idx1=20052&idx2=1'] =
        [200, {}, dop2_leaf(2, 105, { 4 => dop2_field(:i16, 1) }, idx1: 20_052, idx2: 1)]
      expect(dishwasher.setting(20_052).current_value).to eq(1)
    end

    it 'locks while RemoteEnable says 7, and asks AppSupport bit 4 for mobile control', :aggregate_failures do
      state('Status' => 4, 'RemoteEnable' => [7, 0, 0])
      expect(dishwasher.locked?).to be(true)
      expect(dishwasher.mobile_control?).to be(false)
    end

    it 'reads its typed objects at idx 0/1, as the app does', :aggregate_failures do
      %w[1574 1584 131].each do |attribute|
        resources["DOP2/2/#{attribute}?idx1=0&idx2=1"] = [200, {}, dop2_leaf(2, attribute.to_i, {}, idx2: 1)]
      end
      objects = Miele::Sdk::Objects::Dishwasher
      expect([dishwasher.program_context, dishwasher.programs, dishwasher.notifications].map(&:class))
        .to eq([objects::GlobalPsContext, objects::GlobalProgramList, objects::GlobalNtfctnShow])
    end

    it 'reads its latest program runs, which the app reads on DOP2 only' do
      resources['LatestProgramRuns'] = [200, {}, '[]']
      expect(dishwasher.latest_program_runs).to eq([])
    end

    it 'reads its statistics, which the app reads on DOP2 only' do
      resources['Statistics'] = [200, {}, '{"weeks":[]}']
      expect(dishwasher.statistics).to eq('weeks' => [])
    end
  end
end
