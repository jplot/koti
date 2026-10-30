# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { Miele::Sdk.appliance('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:ident) { { 'DeviceType' => 13, 'DeviceIdentLabel' => { 'FabNumber' => fab } } }
  let(:resources) { { '/Devices/' => { fab => { 'href' => "#{fab}/" } }, "/Devices/#{fab}/Ident" => ident } }
  let(:command_answer) { [200, {}, ''] }
  let(:fake) do
    FakeAppliance.start do |request|
      request.verb == 'PUT' ? command_answer : [200, {}, JSON.generate(resources.fetch(request.path, {}))]
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def paths = fake.requests.map(&:path)

  it 'finds its fabrication number', :aggregate_failures do
    2.times { expect(appliance.fab).to eq(fab) }
    expect(paths).to eq(['/Devices/'])
  end

  it 'reads ident and translates the device type', :aggregate_failures do
    expect(appliance.ident).to have_attributes(device_type: 13, device_ident_label: have_attributes(fab_number: fab))
    expect(appliance.device_type).to eq(:oven_microwave)
  end

  it 'reads its supervision and the update of its module as typed values', :aggregate_failures do
    resources["/Devices/#{fab}/SuperVision"] = { 'Enabled' => true, 'ErrorOnly' => false }
    resources['/Update/'] = { 'NewerAvailable' => false, 'UpdateInProgress' => false, 'CurrentVersion' => '31.17' }
    expect(appliance.supervision).to have_attributes(enabled: true, error_only: false, entries: {})
    expect(appliance.software_update).to have_attributes(newer_available: false, current_version: '31.17')
  end

  it 'reads each resource at its path' do
    readers = { settings: "/Devices/#{fab}/Settings",
                update: "/Devices/#{fab}/Update", supervision: "/Devices/#{fab}/SuperVision",
                info: '/Info', host_info: '/Host', software_update: '/Update/' }
    readers.each_key { appliance.public_send(it) }
    expect(paths).to include(*readers.values)
  end

  it 'still reads the Service resource the modules serve' do
    appliance.service
    expect(paths.last).to eq("/Devices/#{fab}/Service")
  end

  it 'reads the services in lower case' do
    appliance.services
    expect(paths.last).to eq("/Devices/#{fab}/services")
  end

  it 'knows every device type of the app' do
    expect([Miele::Sdk::Catalog::DEVICE_TYPES.size, Miele::Sdk::Catalog::DEVICE_TYPES[39]])
      .to eq([74, :electrical_oven_double])
  end

  it 'names the protocol' do
    ident['ProtocolVersion'] = 203
    expect(appliance.protocol).to eq(:lhb_tod2_cooling)
  end

  context 'with a device type missing from the catalog' do
    let(:ident) { { 'DeviceType' => 99 } }

    it 'maps an unknown device type to :unknown' do
      expect(appliance.device_type).to eq(:unknown)
    end
  end

  it 'reads its state' do
    resources["/Devices/#{fab}/State"] = { 'Status' => 1, 'ProgramPhase' => 3329 }
    expect([appliance.state.status, appliance.state.program_phase]).to eq(%i[off heating_up_phase])
  end

  it 'reads program types by the protocol version of its ident', :aggregate_failures do
    ident['ProtocolVersion'] = 4
    resources["/Devices/#{fab}/State"] = { 'ProgramType' => 1 }
    expect(appliance.protocol_version).to eq(4)
    expect(appliance.state.program_type).to eq(:normal_operation)
  end

  it 'names a Dop1 program from the table of its tech type', :aggregate_failures do
    ident.merge!('DeviceType' => 12, 'ProtocolVersion' => 2)
    ident['DeviceIdentLabel']['TechType'] = 'H2160B'
    resources["/Devices/#{fab}/State"] = { 'ProgramID' => 5 }
    expect(appliance.tech_type).to eq('H2160B')
    expect(appliance.state.program).to eq(:fan_plus)
  end

  context 'when sending commands' do
    def sent = fake.requests.select { it.verb == 'PUT' }.map { [it.path, JSON.parse(it.body)] }

    it 'sends the wake command' do
      appliance.wake
      expect(sent).to eq([["/Devices/#{fab}/State", { 'DeviceAction' => 2 }]])
    end

    it 'no longer offers start, stop, pause or the light' do
      expect(%i[start stop pause light_on light_off].select { appliance.respond_to?(it) }).to be_empty
    end

    context 'when the appliance answers 400' do
      let(:command_answer) { [400, {}, ''] }

      it 'treats a 400 answer to a command as done' do
        expect { appliance.wake }.not_to raise_error
      end
    end

    context 'when remote control is off' do
      let(:command_answer) { [403, {}, ''] }

      it 'raises RemoteControlDisabledError when remote control is off' do
        expect { appliance.wake }.to raise_error(Miele::Sdk::RemoteControlDisabledError)
      end
    end
  end
end
