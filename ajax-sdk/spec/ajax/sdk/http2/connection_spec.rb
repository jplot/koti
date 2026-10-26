# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength -- integration specs drive a real socket and a background server

RSpec.describe Ajax::Sdk::Http2::Connection do
  def request_headers(path = '/')
    [%w[:method GET], [':path', path], %w[:scheme http], %w[:authority localhost]]
  end

  def plain_connection(server)
    described_class.new(TCPSocket.new('127.0.0.1', server.port))
  end

  def collect(stream)
    [].tap { |events| stream.each_event { |event| events << event } }
  end

  describe '.open over TLS' do
    it 'negotiates h2 over verified TLS and exchanges a request' do
      server = FakeHttp2Server.new(tls: true) do |_headers, _body, responder|
        responder.respond(headers: [%w[:status 200]])
      end
      connection = described_class.open(host: '127.0.0.1', port: server.port, ca_file: server.ca_file)

      events = collect(connection.request(request_headers, end_stream: true))

      expect(events).to eq([[:headers, [%w[:status 200]]]])
    ensure
      connection&.close
      server.stop
    end

    it 'refuses a server certificate it cannot verify' do
      server = FakeHttp2Server.new(tls: true) { |*| nil }

      expect { described_class.open(host: '127.0.0.1', port: server.port) }
        .to raise_error(OpenSSL::SSL::SSLError)
    ensure
      server.stop
    end
  end

  describe 'a request' do
    it 'reads headers, data and trailers in order' do
      server = FakeHttp2Server.new do |_headers, _body, responder|
        responder.respond(headers: [%w[:status 200]], data: 'hello', trailers: [%w[grpc-status 0]])
      end
      connection = plain_connection(server)

      events = collect(connection.request(request_headers, end_stream: true))

      expect(events).to eq([[:headers, [%w[:status 200]]], [:data, 'hello'], [:trailers, [%w[grpc-status 0]]]])
    ensure
      connection&.close
      server.stop
    end
  end

  describe 'flow control' do
    it 'waits for a WINDOW_UPDATE before sending past the window', :aggregate_failures do
      server = FakeHttp2Server.new(initial_window: 5, auto_window: false) { |*| nil }
      connection = plain_connection(server)
      stream = connection.request(request_headers, end_stream: false)

      writer = Thread.new { stream.write('hello world', end_stream: true) }
      first = server.chunks.pop
      sleep 0.1

      expect(first.last).to eq('hello')
      expect(writer).to be_alive
      server.grant(first.first, 100)
      expect(server.chunks.pop.last).to eq(' world')
      expect(writer.join(2)).to be_truthy
    ensure
      connection&.close
      server.stop
    end
  end

  describe 'control frames' do
    it 'answers a PING with its payload' do
      server = FakeHttp2Server.new { |*| nil }
      connection = plain_connection(server)

      server.send_ping('koti-png')

      expect(server.pongs.pop).to eq('koti-png')
    ensure
      connection&.close
      server.stop
    end

    it 'sends RST_STREAM CANCEL when a stream is cancelled' do
      server = FakeHttp2Server.new { |*| nil }
      connection = plain_connection(server)
      stream = connection.request(request_headers, end_stream: false)

      stream.write('x')
      stream.cancel

      expect(server.resets.pop).to eq([1, 8])
    ensure
      connection&.close
      server.stop
    end

    it 'turns a server RST_STREAM into a reset event' do
      server = FakeHttp2Server.new { |*| nil }
      connection = plain_connection(server)
      stream = connection.request(request_headers, end_stream: true)
      sleep 0.1

      server.send_rst(1, 7)

      expect(collect(stream)).to eq([[:reset, 7]])
    ensure
      connection&.close
      server.stop
    end

    it 'applies the peer MAX_FRAME_SIZE setting' do
      server = FakeHttp2Server.new(max_frame: 20_000) do |_h, _b, responder|
        responder.respond(headers: [%w[:status 200]])
      end
      connection = plain_connection(server)

      collect(connection.request(request_headers, end_stream: true))

      expect(connection.max_frame_size).to eq(20_000)
    ensure
      connection&.close
      server.stop
    end

    it 'fails open streams with ConnectionClosed on GOAWAY' do
      server = FakeHttp2Server.new { |*| nil }
      connection = plain_connection(server)
      stream = connection.request(request_headers, end_stream: true)
      sleep 0.1

      server.send_goaway(0)

      expect { stream.each_event { |_event| nil } }.to raise_error(Ajax::Sdk::Http2::ConnectionClosed)
    ensure
      connection&.close
      server.stop
    end
  end

  describe 'under concurrency' do
    it 'carries 16 streams each sending and receiving 200 KiB within 10 seconds' do
      server = FakeHttp2Server.new do |_headers, body, responder|
        responder.respond(headers: [%w[:status 200]], data: body, trailers: [%w[grpc-status 0]])
      end
      connection = plain_connection(server)
      results = Thread::Queue.new

      threads = Array.new(16) do |index|
        Thread.new do
          payload = index.chr * (200 * 1024)
          stream = connection.request(request_headers, end_stream: false)
          stream.write(payload, end_stream: true)
          echoed = +''.b
          stream.each_event { |type, value| echoed << value if type == :data }
          results << [echoed.bytesize, echoed == payload]
        end
      end
      threads.each { |thread| raise 'stream timed out' unless thread.join(10) }

      sizes = Array.new(16) { results.pop }
      expect(sizes).to all(eq([200 * 1024, true]))
    ensure
      connection&.close
      server.stop
    end
  end
end
# rubocop:enable RSpec/ExampleLength
