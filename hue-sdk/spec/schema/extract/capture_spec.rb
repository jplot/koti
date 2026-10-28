# frozen_string_literal: true

require_relative '../../../schema/extract/capture'

RSpec.describe Schema::Extract::Capture do
  let(:bridge) do
    FakeBridge.serving('GET /clip/v2/resource' => { errors: [], data: [{ id: 'l1', type: 'light', on: { on: true } }] })
  end
  let(:path) { File.join(Dir.mktmpdir, 'capture.json') }

  before { connect_to(bridge) }

  after do
    bridge.stop
    FileUtils.remove_entry(File.dirname(path))
  end

  it 'points the SDK at the bridge the environment names' do
    described_class.configure('HUE_HOST' => '192.0.2.10', 'HUE_BRIDGE_ID' => 'ecb5fafffe000002',
                              'HUE_APPLICATION_KEY' => 'k')
    expect(Hue::Sdk.config.then { [it.host, it.bridge_id, it.application_key] })
      .to eq(['192.0.2.10', 'ecb5fafffe000002', 'k'])
  end

  it 'saves every resource of the bridge, readable by its owner only', :aggregate_failures do
    described_class.write(path)
    expect(JSON.parse(File.read(path))).to eq([{ 'id' => 'l1', 'type' => 'light', 'on' => { 'on' => true } }])
    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end

  it 'leaves a capture it overwrites readable by its owner only' do
    File.write(path, '[]', perm: 0o644)
    described_class.write(path)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
  end
end
