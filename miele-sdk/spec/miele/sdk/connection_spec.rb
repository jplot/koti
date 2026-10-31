# frozen_string_literal: true

RSpec.describe Miele::Sdk::Connection do
  let(:answer) { [200, {}, '{"000123456789":{"href":"000123456789/"}}'] }
  let(:appliance) { FakeAppliance.start { answer } }

  before { connect_to(appliance) }

  after { appliance.stop }

  def call(verb, path, body: nil) = described_class.request('127.0.0.1', verb, path, body:)

  it 'decrypts a signed response', :aggregate_failures do
    response = call(:get, '/Devices/')
    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to eq('000123456789' => { 'href' => '000123456789/' })
    expect(appliance.requests.last.verified).to be(true)
  end

  it 'sends the PUT body encrypted and signed', :aggregate_failures do
    call(:put, '/Devices/000123456789/State', body: '{"Light":1}')
    request = appliance.requests.last
    expect(request).to have_attributes(verb: 'PUT', verified: true)
    expect(JSON.parse(request.body)).to eq('Light' => 1)
  end

  it 'pads a DOP2 body to 32 bytes on the local channel', :aggregate_failures do
    body = ['000e0002063200000000000100010404'].pack('H*')
    described_class.local('127.0.0.1').request(:put, '/Devices/000123456789/DOP2/2/1586', body:, kind: :dop2)
    expect(appliance.requests.last).to have_attributes(verb: 'PUT', verified: true)
    expect(appliance.requests.last.headers['content-length']).to eq('32')
  end

  context 'when the response is signed with another key' do
    let(:appliance) { FakeAppliance.start(answer_key: 'AB' * 64) { answer } }

    it 'raises SignatureError' do
      expect { call(:get, '/Devices/') }.to raise_error(Miele::Sdk::SignatureError)
    end
  end

  context 'when the answer carries no signature' do
    let(:appliance) { FakeAppliance.start(unsigned: true) { answer } }

    it 'raises SignatureError' do
      expect { call(:get, '/Devices/') }.to raise_error(Miele::Sdk::SignatureError, /not signed/)
    end
  end

  context 'when the appliance answers 403' do
    let(:answer) { [403, {}, ''] }

    it 'raises AuthenticationError on a read' do
      expect { call(:get, '/Devices/') }.to raise_error(Miele::Sdk::AuthenticationError, /group_key/)
    end

    it 'raises RemoteControlDisabledError on a write' do
      expect { call(:put, '/Devices/000123456789/State', body: '{"Light":1}') }
        .to raise_error(Miele::Sdk::RemoteControlDisabledError, /Mobile Controllable/)
    end
  end

  context 'when the appliance answers 404' do
    let(:answer) { [404, {}, ''] }

    it 'raises NotFoundError' do
      expect { call(:get, '/Devices/000123456789/DOP2/2/1585') }.to raise_error(Miele::Sdk::NotFoundError)
    end
  end

  it 'raises ConnectionError naming the host when it is unreachable' do
    Miele::Sdk.config.port = TCPServer.new('127.0.0.1', 0).then { |server| server.addr[1].tap { server.close } }
    expect { call(:get, '/Devices/') }.to raise_error(Miele::Sdk::ConnectionError, /127\.0\.0\.1:/)
  end

  context 'when the environment names a proxy' do
    around do |example|
      saved = ENV.fetch('http_proxy', nil)
      ENV['http_proxy'] = "http://127.0.0.1:#{appliance.port}"
      example.run
    ensure
      ENV['http_proxy'] = saved
    end

    it 'connects to the appliance itself', :aggregate_failures do
      Miele::Sdk.config.open_timeout = 0.2
      expect { described_class.request('192.0.2.20', :get, '/Devices/') }.to raise_error(Miele::Sdk::ConnectionError)
      expect(appliance.requests).to be_empty
    end
  end

  it 'rejects a group key that is not 128 hex digits' do
    Miele::Sdk.config.group_key = 'abc'
    expect { call(:get, '/Devices/') }.to raise_error(Miele::Sdk::ConfigurationError, /group_key/)
  end
end
