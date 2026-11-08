# frozen_string_literal: true

require 'fileutils'
require 'openssl'
require 'socket'
require 'tmpdir'

# A real TLS server speaking enough MQTT 3.1.1 to stand in for the broker of Hue Secure. It answers CONNECT with
# +connack+ (or closes on +:drop+, keeps silent on +:silent+) and reads SUBSCRIBE; then the spec's script drives the
# connection, or else it sends SUBACK and +publishes+ and closes. It keeps the protocols the client offered over ALPN
# and every packet it sent.
class FakeMqtt
  include TestCertificates

  Packet = Data.define(:type, :flags, :body)

  attr_reader :port, :ca_file, :offered, :packets

  def self.start(connack: 0, name: 'localhost', publishes: [], &script)
    new(connack, name, publishes, script).tap(&:start)
  end

  def initialize(connack, name, publishes, script)
    @connack = connack
    @name = name
    @script = script || ->(broker, socket) { broker.default(socket, publishes) }
    @packets = []
  end

  def start
    authority, authority_key = certificate_authority
    @directory = Dir.mktmpdir
    @ca_file = File.join(@directory, 'ca.pem').tap { File.write(it, authority.to_pem) }
    tcp = TCPServer.new('127.0.0.1', 0)
    @port = tcp.addr[1]
    @server = OpenSSL::SSL::SSLServer.new(tcp, context(authority, authority_key))
    @thread = Thread.new { serve }
  end

  def stop
    @server.close
    @thread.join(5)
    FileUtils.remove_entry(@directory)
  end

  def connect = packets.find { it.type == 1 }

  def default(socket, publishes)
    socket.write(suback)
    publishes.each { |topic, payload| socket.write(publish(topic, payload)) }
    read(socket) while socket.wait_readable(0.2)
  end

  # Ends the TLS session and reads until the client closes, so that an acknowledgement still on its way draws no reset.
  def finish(socket)
    socket.close_write
    read(socket) while socket.wait_readable(1)
  end

  def suback = [0x90, 3, 0, 1, 1].pack('C*')

  def publish(topic, payload, id: nil)
    body = [topic.bytesize].pack('n') + topic.b + (id ? [id].pack('n') : ''.b) + payload.b
    [id ? 0x32 : 0x30, body.bytesize].pack('CC') + body
  end

  def read(socket)
    header = socket.readbyte
    (@packets << Packet.new(type: header >> 4, flags: header & 0xf, body: socket.read(length(socket)).to_s)).last
  end

  def length(socket)
    length = shift = 0
    loop do
      byte = socket.readbyte
      length |= (byte & 0x7f) << shift
      shift += 7
      return length if byte < 0x80
    end
  end

  private

  def context(authority, authority_key)
    key = OpenSSL::PKey::EC.generate('prime256v1')
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = leaf(key, authority, authority_key)
      context.key = key
      context.alpn_select_cb = ->(protocols) { (@offered = protocols).first }
    end
  end

  def leaf(key, authority, authority_key)
    cert = certificate("/CN=#{@name}", key, authority, authority_key)
    extensions = OpenSSL::X509::ExtensionFactory.new(authority, cert)
    cert.add_extension(extensions.create_extension('subjectAltName', "DNS:#{@name}"))
    cert.sign(authority_key, OpenSSL::Digest.new('SHA256'))
  end

  def serve
    socket = @server.accept
    read(socket)
    return if @connack == :drop
    return socket.wait_readable(3) if @connack == :silent

    socket.write([0x20, 2, 0, @connack].pack('C*'))
    @script.call(self, socket) if @connack.zero? && read(socket)
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  ensure
    socket&.close
  end
end
