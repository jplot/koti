# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../schema/extract/capture'

RSpec.describe Schema::Extract::Capture do
  let(:fab) { '000123456789' }
  let(:resources) do
    { '/Devices/' => { fab => { 'href' => "#{fab}/" } }, "/Devices/#{fab}/Ident" => { 'DeviceType' => 13 },
      '/Update/' => { 'NewerAvailable' => false } }
  end
  let(:busy) { false }
  let(:fake) do
    FakeAppliance.start do |request|
      next [503, {}, ''] if busy

      resources.key?(request.path) ? [200, {}, JSON.generate(resources[request.path])] : [404, {}, '']
    end
  end
  let(:path) { File.join(Dir.mktmpdir, 'capture.json') }

  before { connect_to(fake) }

  after do
    fake.stop
    FileUtils.remove_entry(File.dirname(path))
  end

  it 'reads every resource of each appliance, its fabrication number replaced', :aggregate_failures do
    capture = described_class.read(['127.0.0.1']).fetch('127.0.0.1')
    expect(capture.slice('/Devices/{fab}/Ident', '/Update/'))
      .to eq('/Devices/{fab}/Ident' => { 'DeviceType' => 13 }, '/Update/' => { 'NewerAvailable' => false })
    expect(capture['/Devices/{fab}/SuperVision']).to eq('error' => 'Miele::Sdk::NotFoundError')
  end

  it 'reads the resources of the appliance and of its Wi-Fi module' do
    expect(described_class.read(['127.0.0.1']).fetch('127.0.0.1').keys).to eq(
      ['/Devices/', *%w[/ /Ident /State /Settings /Service /Update /SuperVision].map { "/Devices/{fab}#{it}" },
       '/', '/Info', '/Host', '/Update/', '/Subscriptions/']
    )
  end

  context 'when an appliance refuses every request' do
    let(:busy) { true }

    it 'notes it and goes on' do
      expect(described_class.read(['127.0.0.1'])).to eq('127.0.0.1' => { 'error' => 'Miele::Sdk::ResponseError' })
    end
  end

  it 'only reads' do
    described_class.read(['127.0.0.1'])
    expect(fake.requests.map(&:verb).uniq).to eq(['GET'])
  end

  it 'saves the capture readable by its owner only, even over an earlier one', :aggregate_failures do
    File.write(path, '{}', perm: 0o644)
    described_class.write(path, ['127.0.0.1'])
    expect(JSON.parse(File.read(path)).dig('127.0.0.1', '/Update/')).to eq('NewerAvailable' => false)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end

  it 'points the SDK at the group the environment names' do
    described_class.configure('MIELE_GROUP_ID' => '00000000000000AA', 'MIELE_GROUP_KEY' => 'BB' * 64)
    expect(Miele::Sdk.config.then { [it.group_id, it.group_key] }).to eq(['00000000000000AA', 'BB' * 64])
  end
end
