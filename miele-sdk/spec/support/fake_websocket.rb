# frozen_string_literal: true

require 'digest'
require 'socket'

# A local ws:// server standing in for the Miele cloud websocket. Each connection answers the handshake, runs the
# spec's script with a Connection to send frames, then keeps every frame the client sends until it closes.
class FakeWebsocket
  GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  Frame = Data.define(:opcode, :payload)

  # One client connection, as the script sees it.
  class Connection
    attr_reader :request, :frames

    def initialize(socket, request)
      @socket = socket
      @request = request
      @frames = []
    end

    def send_binary(bytes, fin: true, opcode: 2) = @socket.write(FakeWebsocket.frame(opcode, bytes, fin:))

    def send_continuation(bytes) = send_binary(bytes, opcode: 0)

    def send_ping(payload) = @socket.write(FakeWebsocket.frame(9, payload))

    def drop = @socket.close

    def dropped? = @socket.closed?

    def read_frames
      until @socket.closed? || (frame = FakeWebsocket.read(@socket)).nil?
        @frames << frame
        break if frame.opcode == 8
      end
    end
  end

  attr_reader :connections

  def self.start(accept: nil, refuse: 0, &script) = new(accept, refuse, script).tap(&:start)

  def self.frame(opcode, payload, fin: true)
    head = [(fin ? 0x80 : 0) | opcode].pack('C')
    size = payload.bytesize
    head + length(size) + payload.b
  end

  def self.length(size)
    return [size].pack('C') if size < 126
    return [126, size].pack('Cn') if size < 65_536

    [127, size].pack('CQ>')
  end

  def self.read(socket)
    first, second = socket.read(2)&.unpack('CC')
    return unless second

    size = size(socket, second & 0x7F)
    mask = second.anybits?(0x80) ? socket.read(4).bytes : [0, 0, 0, 0]
    Frame.new(opcode: first & 0x0F, payload: unmask(socket.read(size), mask))
  end

  def self.unmask(bytes, mask) = bytes.bytes.each_with_index.map { |byte, index| byte ^ mask[index % 4] }.pack('C*')

  def self.size(socket, size)
    return size if size < 126

    socket.read(size == 126 ? 2 : 8).unpack1(size == 126 ? 'n' : 'Q>')
  end

  def initialize(accept, refuse, script)
    @accept = accept
    @refuse = refuse
    @script = script || ->(_connection, _index) {}
    @connections = []
  end

  def start
    @server = TCPServer.new('127.0.0.1', 0)
    @thread = Thread.new do
      loop { serve(@server.accept) }
    rescue IOError
      nil
    end
  end

  def url = "ws://127.0.0.1:#{@server.addr[1]}"

  def stop
    @server.close
    @thread.join(5)
  end

  private

  def serve(socket)
    connection = Connection.new(socket, handshake_request(socket))
    @connections << connection
    return socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n") if @connections.size <= @refuse

    respond(socket, connection.request)
    @script.call(connection, @connections.size)
    connection.read_frames
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE
    nil
  ensure
    socket.close unless socket.closed?
  end

  def respond(socket, request)
    socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" \
                 "Sec-WebSocket-Accept: #{@accept || accept(request)}\r\n\r\n")
  end

  def handshake_request(socket)
    line = socket.gets("\r\n")
    headers = {}
    while (header = socket.gets("\r\n")) && header != "\r\n"
      name, value = header.chomp.split(': ', 2)
      headers[name.downcase] = value
    end
    { line: line.chomp, headers: }
  end

  def accept(request) = [Digest::SHA1.digest(request[:headers]['sec-websocket-key'] + GUID)].pack('m0')
end
