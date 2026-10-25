# frozen_string_literal: true

RSpec.describe Hue::Sdk::Client do
  let(:status) { 200 }
  let(:payload) { { data: [{ id: 'l1' }], errors: [] } }
  let(:bridge) { FakeBridge.start { [status, { 'Content-Type' => 'application/json' }, JSON.generate(payload)] } }

  before do
    Hue::Sdk.configure do |config|
      config.host = '127.0.0.1'
      config.port = bridge.port
      config.bridge_id = 'ECB5FAFFFE000001'
      config.ca_file = bridge.ca_file
      config.application_key = 'test-key'
    end
  end

  after { bridge.stop }

  it 'returns the data array of the response' do
    expect(described_class.get('/resource/light')).to eq([{ 'id' => 'l1' }])
  end

  it 'targets the CLIP v2 path with the application key', :aggregate_failures do
    described_class.put('/resource/light/l1', body: { on: { on: true } })
    request = bridge.requests.last
    expect(request).to have_attributes(verb: 'PUT', path: '/clip/v2/resource/light/l1', body: '{"on":{"on":true}}')
    expect(request.headers).to include('hue-application-key' => 'test-key', 'content-type' => 'application/json')
  end

  context 'when the bridge reports a partial success' do
    let(:status) { 207 }
    let(:payload) { { data: [], errors: [{ description: 'device (light) has communication issues' }] } }

    it 'raises ResponseError with the error descriptions' do
      expect { described_class.put('/resource/light/l1', body: { on: { on: true } }) }
        .to raise_error(
          an_instance_of(Hue::Sdk::ResponseError)
            .and(having_attributes(status: 207, errors: ['device (light) has communication issues']))
        )
    end
  end

  {
    403 => Hue::Sdk::AuthenticationError,
    404 => Hue::Sdk::NotFoundError,
    429 => Hue::Sdk::RateLimitError,
    500 => Hue::Sdk::ResponseError
  }.each do |code, error_class|
    context "when the bridge answers #{code}" do
      let(:status) { code }

      it "raises #{error_class.name.split('::').last}" do
        expect { described_class.get('/resource/light') }.to raise_error(error_class)
      end
    end
  end

  context 'when the bridge answers with a body that is not JSON' do
    let(:bridge) { FakeBridge.start { [503, { 'Content-Type' => 'text/html' }, '<html>busy</html>'] } }

    it 'raises ResponseError without descriptions' do
      expect { described_class.get('/resource/light') }
        .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 503, errors: [])))
    end
  end

  it 'raises AuthenticationError before any request when the key is missing', :aggregate_failures do
    Hue::Sdk.config.application_key = nil
    expect { described_class.get('/resource/light') }.to raise_error(Hue::Sdk::AuthenticationError)
    expect(bridge.requests).to be_empty
  end
end
