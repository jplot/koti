# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { Miele::Sdk.appliance('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:ident) { { 'DeviceType' => 13, 'DeviceIdentLabel' => { 'FabNumber' => fab } } }
  let(:resources) { { '/Devices/' => { fab => { 'href' => "#{fab}/" } }, "/Devices/#{fab}/Ident" => ident } }
  let(:fake) { FakeAppliance.start { |request| [200, {}, JSON.generate(resources.fetch(request.path, {}))] } }

  before { connect_to(fake) }

  after { fake.stop }

  def paths = fake.requests.map(&:path)

  it 'finds its fabrication number', :aggregate_failures do
    2.times { expect(appliance.fab).to eq(fab) }
    expect(paths).to eq(['/Devices/'])
  end

  it 'reads ident and translates the device type', :aggregate_failures do
    expect(appliance.ident).to eq(ident)
    expect(appliance.device_type).to eq(:oven_microwave)
  end

  it 'reads each resource at its path' do
    readers = { settings: "/Devices/#{fab}/Settings", service: "/Devices/#{fab}/Service",
                update: "/Devices/#{fab}/Update", supervision: "/Devices/#{fab}/SuperVision",
                info: '/Info', host_info: '/Host', software_update: '/Update/' }
    readers.each_key { appliance.public_send(it) }
    expect(paths).to include(*readers.values)
  end

  context 'with a device type missing from the catalog' do
    let(:ident) { { 'DeviceType' => 99 } }

    it 'maps an unknown device type to :unknown' do
      expect(appliance.device_type).to eq(:unknown)
    end
  end
end
