# frozen_string_literal: true

require 'socket'

RSpec.describe Ajax::Sdk, '.sia_events' do
  let(:port) { TCPServer.open('127.0.0.1', 0) { it.addr[1] } }

  before do
    described_class.configure do |config|
      config.sia_host = '127.0.0.1'
      config.sia_port = port
      config.sia_account = 'AAA'
    end
  end

  def send_when_listening(frame)
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write(frame)
    socket.wait_readable(1) && socket.gets("\r")
  rescue Errno::ECONNREFUSED
    sleep(0.02) && retry
  ensure
    socket&.close
  end

  it 'yields the events of the configured receiver lazily, then frees its port', :aggregate_failures do
    reader = Thread.new { described_class.sia_events.first(1) }

    send_when_listening(sia_frame('"SIA-DCS"0001L0#AAA[#AAA|Nri2/BA7]'))

    expect(reader.value.first).to have_attributes(code: 'BA', zone: '2', text: '7')
    expect { TCPServer.new('127.0.0.1', port).close }.not_to raise_error
  end

  it 'refuses to start without an account' do
    described_class.configure { |config| config.sia_account = nil }

    expect { described_class.sia_events.first }.to raise_error(Ajax::Sdk::ConfigurationError, /sia_account/)
  end
end
