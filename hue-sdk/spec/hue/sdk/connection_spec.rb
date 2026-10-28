# frozen_string_literal: true

RSpec.describe Hue::Sdk::Connection do
  let(:bridge) { FakeBridge.start }

  before do
    Hue::Sdk.configure do |config|
      config.host = '127.0.0.1'
      config.port = bridge.port
      config.bridge_id = 'ECB5FAFFFE000001'
      config.ca_file = bridge.ca_file
    end
  end

  after { bridge.stop }

  def fetch(path) = described_class.request(:get, path).body

  it 'embeds the Signify root-bridge CA', :aggregate_failures do
    cert = OpenSSL::X509::Certificate.new(File.read(Hue::Sdk::Configuration::DEFAULT_CA_FILE))
    expect(cert.subject.to_s).to eq('/C=NL/O=Philips Hue/CN=root-bridge')
    expect(OpenSSL::Digest::SHA256.hexdigest(cert.to_der).upcase)
      .to eq('F0BD8E6509E82F774D63BC009D5388C969FE3DCF7D6D541D6351B72B898D8ACF')
  end

  it 'answers when the certificate CN matches the bridge id' do
    expect(described_class.request(:get, '/api/0/config').body).to eq('ok')
  end

  it 'raises TLSError when the CN differs from the bridge id' do
    Hue::Sdk.config.bridge_id = 'ECB5FAFFFE000002'
    expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::TLSError, /ECB5FAFFFE000002/)
  end

  context 'with a certificate from another CA' do
    let(:bridge) { FakeBridge.start(foreign_ca: true) }

    it 'raises TLSError' do
      expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::TLSError)
    end
  end

  it 'raises ConnectionError when no host is configured' do
    Hue::Sdk.config.host = nil
    expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::ConnectionError, /host is not configured/)
  end

  it 'raises TLSError when no bridge id is configured' do
    Hue::Sdk.config.bridge_id = nil
    expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::TLSError, /bridge_id is not configured/)
  end

  it 'raises ConnectionError naming the host when it is unreachable' do
    Hue::Sdk.config.port = TCPServer.new('127.0.0.1', 0).then { |server| server.addr[1].tap { server.close } }
    expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::ConnectionError, /127\.0\.0\.1:/)
  end

  context 'when the environment names a proxy' do
    let(:proxy) { TCPServer.new('127.0.0.1', 0) }

    around do |example|
      saved = ENV.fetch('http_proxy', nil)
      ENV['http_proxy'] = "http://127.0.0.1:#{proxy.addr[1]}"
      example.run
    ensure
      ENV['http_proxy'] = saved
      proxy.close
    end

    it 'connects to the bridge itself', :aggregate_failures do
      Hue::Sdk.configure do |config|
        config.host = '192.0.2.20'
        config.open_timeout = 0.2
        config.read_timeout = 0.2
      end
      expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::ConnectionError, /192\.0\.2\.20/)
      expect(proxy.accept_nonblock(exception: false)).to eq(:wait_readable)
    end
  end

  context 'when the bridge drops the connection without closing TLS' do
    let(:bridge) { FakeBridge.start { [200, {}, 'partial', :cut] } }

    it 'raises ConnectionError, not TLSError' do
      expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::ConnectionError, /127\.0\.0\.1:/)
    end
  end

  it 'reopens a keep-alive connection after the bridge was unreachable', :aggregate_failures do
    described_class.request(:get, '/')
    bridge.down!
    expect { described_class.request(:get, '/') }.to raise_error(Hue::Sdk::ConnectionError)
    bridge.up!
    3.times { described_class.request(:get, '/') }
    expect(bridge.connections).to eq(2)
  end

  context 'when several threads share the SDK' do
    let(:bridge) { FakeBridge.start { |request| [200, {}, request.path.tap { sleep(rand * 0.005) }] } }

    it 'never mixes responses between threads' do
      paths = Array.new(8) { |thread| Array.new(25) { |n| "/echo/#{thread}/#{n}" } }
      threads = paths.map { |slice| Thread.new { slice.map { |path| [path, fetch(path)] } } }
      results = threads.flat_map(&:value)
      expect(results).to all(satisfy { |path, body| path == body })
    end
  end
end
