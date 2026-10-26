# frozen_string_literal: true

require 'socket'
require 'openssl'
require 'tempfile'

# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity -- an in-process test server

# A minimal in-process HTTP/2 server for the connection specs. It completes the h2 handshake, reads
# requests, and for each one runs the block with the decoded headers, the request body and a
# responder. In +auto_window: true+ it grants flow-control credit as it reads; in manual mode it
# leaves crediting to the test via {#grant} and exposes each DATA payload on {#chunks}.
class FakeHttp2Server
  include Ajax::Sdk::Http2::Frames

  Responder = Struct.new(:server, :stream_id) do
    def respond(headers:, data: '', trailers: nil)
      server.send_headers(stream_id, headers, end_stream: data.empty? && trailers.nil?)
      server.send_body(stream_id, data.b, end_stream: trailers.nil?) unless data.empty?
      server.send_headers(stream_id, trailers, end_stream: true) if trailers
    end
  end

  attr_reader :port, :ca_file, :chunks, :pongs, :resets

  def initialize(tls: false, initial_window: nil, max_frame: nil, auto_window: true, &handler)
    @handler = handler
    @initial_window = initial_window
    @max_frame = max_frame
    @auto_window = auto_window
    @tls = tls
    @chunks = Thread::Queue.new
    @pongs = Thread::Queue.new
    @resets = Thread::Queue.new
    @started = Thread::Queue.new
    @encoder = Ajax::Sdk::Http2::Hpack::Encoder.new
    @decoder = Ajax::Sdk::Http2::Hpack::Decoder.new
    @write_mutex = Mutex.new
    @bodies = Hash.new { |hash, key| hash[key] = +''.b }
    @headers = {}
    @listener = TCPServer.new('127.0.0.1', 0)
    @port = @listener.addr[1]
    build_tls if tls
    @thread = Thread.new { accept_and_serve }
  end

  def await_start = @started.push(@started.pop)

  def grant(stream_id, increment)
    await_start
    @write_mutex.synchronize do
      @socket.write(frame(WINDOW_UPDATE, 0, 0, [increment].pack('N')))
      @socket.write(frame(WINDOW_UPDATE, 0, stream_id, [increment].pack('N')))
    end
  end

  def stop
    @listener.close
    @socket&.close
  rescue IOError
    nil
  ensure
    @thread.kill
    @thread.join
  end

  def send_ping(payload = '12345678')
    await_start
    @write_mutex.synchronize { @socket.write(frame(PING, 0, 0, payload.b)) }
  end

  def send_goaway(last_stream_id = 0)
    await_start
    @write_mutex.synchronize { @socket.write(frame(GOAWAY, 0, 0, [last_stream_id, 0].pack('NN'))) }
  end

  def send_rst(stream_id, code)
    await_start
    @write_mutex.synchronize { @socket.write(frame(RST_STREAM, 0, stream_id, [code].pack('N'))) }
  end

  def send_headers(stream_id, headers, end_stream:)
    flags = END_HEADERS | (end_stream ? END_STREAM : 0)
    @write_mutex.synchronize { @socket.write(frame(HEADERS, flags, stream_id, @encoder.encode(headers))) }
  end

  def send_body(stream_id, data, end_stream:)
    offset = 0
    while offset < data.bytesize
      slice = data.byteslice(offset, 16_384)
      offset += slice.bytesize
      last = end_stream && offset >= data.bytesize
      @write_mutex.synchronize { @socket.write(frame(DATA, last ? END_STREAM : 0, stream_id, slice)) }
    end
  end

  private

  def accept_and_serve
    raw = @listener.accept
    @socket = @tls ? accept_tls(raw) : raw
    @started.push(true)
    handshake
    read_loop
  rescue IOError, OpenSSL::SSL::SSLError
    nil
  end

  def accept_tls(raw)
    ssl = OpenSSL::SSL::SSLSocket.new(raw, @tls_context)
    ssl.sync_close = true
    ssl.accept
    ssl
  end

  def handshake
    @socket.read(Ajax::Sdk::Http2::PREFACE.bytesize)
    settings = +''.b
    settings << [4, @initial_window].pack('nN') if @initial_window
    settings << [5, @max_frame].pack('nN') if @max_frame
    @socket.write(frame(SETTINGS, 0, 0, settings))
  end

  def read_loop
    loop { dispatch(Ajax::Sdk::Http2::Frame.read(@socket)) }
  end

  def dispatch(frame)
    case frame.type
    when SETTINGS then @socket.write(frame(SETTINGS, ACK, 0, ''.b)) unless frame.flag?(ACK)
    when PING then on_ping(frame)
    when HEADERS then on_headers(frame)
    when DATA then on_data(frame)
    when RST_STREAM then @resets << [frame.stream_id, frame.payload.unpack1('N')]
    when GOAWAY then raise IOError
    end
  end

  def on_ping(frame)
    return @pongs << frame.payload if frame.flag?(ACK)

    @write_mutex.synchronize { @socket.write(frame(PING, ACK, 0, frame.payload)) }
  end

  def on_headers(frame)
    @headers[frame.stream_id] = @decoder.decode(frame.payload)
    finish(frame.stream_id) if frame.flag?(END_STREAM)
  end

  def on_data(frame)
    @bodies[frame.stream_id] << frame.payload
    @chunks << [frame.stream_id, frame.payload]
    grant(frame.stream_id, frame.payload.bytesize) if @auto_window && !frame.payload.empty?
    finish(frame.stream_id) if frame.flag?(END_STREAM)
  end

  def finish(stream_id)
    headers = @headers.delete(stream_id)
    body = @bodies.delete(stream_id) || ''.b
    Thread.new { @handler.call(headers, body, Responder.new(self, stream_id)) }
  end

  def frame(type, flags, stream_id, payload)
    Ajax::Sdk::Http2::Frame.new(type:, flags:, stream_id:, payload:).to_s
  end

  def build_tls
    key = OpenSSL::PKey::RSA.new(2048)
    cert = self_signed(key)
    @ca_file = write_pem(cert)
    @tls_context = OpenSSL::SSL::SSLContext.new
    @tls_context.add_certificate(cert, key)
    @tls_context.alpn_select_cb = ->(protocols) { protocols.include?('h2') ? 'h2' : nil }
  end

  def self_signed(key)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    add_san(cert)
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
  end

  def add_san(cert)
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = cert
    cert.add_extension(factory.create_extension('subjectAltName', 'DNS:localhost,IP:127.0.0.1'))
  end

  def write_pem(cert)
    file = Tempfile.new(['fake-h2-ca', '.pem'])
    file.write(cert.to_pem)
    file.close
    file.path
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
