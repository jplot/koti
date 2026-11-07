# frozen_string_literal: true

require 'openssl'
require 'socket'
require 'tmpdir'

# A real TLS server, for +localhost+, speaking enough MQTT 3.1.1 to stand in for the broker of Hue Secure. It answers
# CONNECT with +connack+ (or closes on +:drop+), SUBSCRIBE with SUBACK, then sends +publishes+ and closes. It keeps
# the protocols the client offered over ALPN and every packet the client sent.
class FakeMqtt
  include TestCertificates

  Packet = Data.define(:type, :body)

  attr_reader :port, :ca_file, :offered, :packets

  def self.start(connack: 0, publishes: []) = new(connack, publishes).tap(&:start)

  def initialize(connack, publishes)
    @connack = connack
    @publishes = publishes
    @packets = []
  end

  def start
    authority, authority_key = certificate_authority
    @ca_file = File.join(Dir.mktmpdir, 'ca.pem').tap { File.write(it, authority.to_pem) }
    tcp = TCPServer.new('127.0.0.1', 0)
    @port = tcp.addr[1]
    @server = OpenSSL::SSL::SSLServer.new(tcp, context(authority, authority_key))
    @thread = Thread.new { serve }
  end

  def stop
    @server.close
    @thread.join(5)
  end

  def connect = packets.find { it.type == 1 }

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
    cert = certificate('/CN=localhost', key, authority, authority_key)
    extensions = OpenSSL::X509::ExtensionFactory.new(authority, cert)
    cert.add_extension(extensions.create_extension('subjectAltName', 'DNS:localhost'))
    cert.sign(authority_key, OpenSSL::Digest.new('SHA256'))
  end

  def serve
    socket = @server.accept
    read(socket)
    return if @connack == :drop

    socket.write([0x20, 2, 0, @connack].pack('C*'))
    return unless @connack.zero?

    follow(socket)
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  ensure
    socket&.close
  end

  def follow(socket)
    read(socket)
    socket.write([0x90, 3, 0, 1, 0].pack('C*'))
    @publishes.each { |topic, payload| socket.write(publish(topic, payload)) }
    read(socket) while socket.wait_readable(0.2)
  end

  def read(socket)
    header = socket.readbyte
    length = shift = 0
    loop do
      byte = socket.readbyte
      length |= (byte & 0x7f) << shift
      shift += 7
      break if byte < 0x80
    end
    @packets << Packet.new(type: header >> 4, body: socket.read(length).to_s)
  end

  def publish(topic, payload)
    body = [topic.bytesize].pack('n') + topic + payload
    [0x30, body.bytesize].pack('CC') + body
  end
end
