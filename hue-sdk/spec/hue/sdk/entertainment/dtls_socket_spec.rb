# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'hue/sdk/entertainment'

RSpec.describe Hue::Sdk::Entertainment::DtlsSocket do
  let(:openssl) { ENV.fetch('HUE_SDK_OPENSSL', 'openssl') }
  let(:identity) { 'koti-test-identity' }
  let(:key) { '0123456789abcdef0123456789abcdef' }
  let(:port) { UDPSocket.new.tap { it.bind('127.0.0.1', 0) }.then { |socket| socket.addr[1].tap { socket.close } } }

  before { skip "#{openssl} not found" unless system(openssl, 'version', out: File::NULL, err: File::NULL) }

  def serve(server_key = key)
    command = [openssl, 's_server', '-dtls1_2', '-nocert', '-psk', server_key, '-psk_identity', identity,
               '-cipher', 'PSK-AES128-GCM-SHA256', '-accept', "127.0.0.1:#{port}"]
    Open3.popen2e(*command) do |_input, output, server|
      read_until(output, 'ACCEPT')
      yield output
    ensure
      Process.kill('TERM', server.pid)
    end
  end

  def read_until(output, text)
    buffer = +''
    Timeout.timeout(5) { buffer << output.readpartial(4096) until buffer.include?(text) }
    buffer
  end

  def connect(psk: [key].pack('H*')) = described_class.open(host: '127.0.0.1', port:, identity:, psk:)

  it 'handshakes with an OpenSSL PSK server' do
    received = serve do |output|
      connect.tap { it.write('ping') }.close
      read_until(output, 'ping')
    end
    expect(received).to include('ping')
  end

  it 'raises ConnectionError when the server holds another key' do
    serve('fedcba9876543210fedcba9876543210') do
      expect { connect }.to raise_error(Hue::Sdk::ConnectionError, /127\.0\.0\.1:\d+: DTLS handshake failed/)
    end
  end

  it 'raises ConnectionError when nothing answers' do
    expect { connect }.to raise_error(Hue::Sdk::ConnectionError, /DTLS handshake failed/)
  end

  it 'refuses to write once closed' do
    socket = serve { connect.tap(&:close) }
    expect { socket.write('late') }.to raise_error(IOError, /closed/)
  end
end
