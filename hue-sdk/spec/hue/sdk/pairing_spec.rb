# frozen_string_literal: true

RSpec.describe Hue::Sdk::Pairing do
  let(:client_key) { '0123456789ABCDEF0123456789ABCDEF' }
  let(:reply) { [{ success: { username: 'app-key', clientkey: client_key } }] }
  let(:bridge) { FakeBridge.start { [200, { 'Content-Type' => 'application/json' }, JSON.generate(reply)] } }

  before do
    Hue::Sdk.configure do |config|
      config.host = '127.0.0.1'
      config.port = bridge.port
      config.bridge_id = 'ECB5FAFFFE000001'
      config.ca_file = bridge.ca_file
    end
  end

  after { bridge.stop }

  it 'returns the credentials' do
    expect(Hue::Sdk.pair(app_name: 'koti', instance_name: 'mac'))
      .to eq(described_class::Credentials.new(application_key: 'app-key', client_key:))
  end

  it 'asks the bridge for an application key and a client key' do
    Hue::Sdk.pair(app_name: 'koti', instance_name: 'mac')
    expect(bridge.requests.last).to have_attributes(
      verb: 'POST', path: '/api', body: '{"devicetype":"koti#mac","generateclientkey":true}'
    )
  end

  it 'truncates the instance name to 19 characters' do
    Hue::Sdk.pair(app_name: 'koti', instance_name: 'a' * 30)
    expect(JSON.parse(bridge.requests.last.body)['devicetype']).to eq("koti##{'a' * 19}")
  end

  it 'rejects an app name longer than 20 characters', :aggregate_failures do
    expect { Hue::Sdk.pair(app_name: 'a' * 21, instance_name: 'mac') }.to raise_error(ArgumentError)
    expect(bridge.requests).to be_empty
  end

  context 'when the link button was not pressed' do
    let(:reply) { [{ error: { type: 101, address: '', description: 'link button not pressed' } }] }

    it 'raises LinkButtonNotPressedError' do
      expect { Hue::Sdk.pair(app_name: 'koti', instance_name: 'mac') }
        .to raise_error(Hue::Sdk::LinkButtonNotPressedError, 'link button not pressed')
    end
  end

  context 'when the bridge refuses for another reason' do
    let(:reply) { [{ error: { type: 7, address: '/devicetype', description: 'invalid value' } }] }

    it 'raises ResponseError with the description' do
      expect { Hue::Sdk.pair(app_name: 'koti', instance_name: 'mac') }
        .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(errors: ['invalid value'])))
    end
  end
end
