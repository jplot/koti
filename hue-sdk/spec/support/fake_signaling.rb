# frozen_string_literal: true

require 'openssl'
require 'socket'
require 'websocket/driver'

# Kinesis Video's signaling WebSocket for one connection, over TLS as AWS serves it: its CA joins the default store
# the gem trusts AWS with. It keeps the request's query and each message received, and calls the spec's script with
# :open, then with each message; the script answers through #say, #hang_up and #drop.
class FakeSignaling
  include TestCertificates

  Wire = Data.define(:io) do
    def write(data) = io.write(data)
  end

  attr_reader :query

  def self.start(refuse: nil, &script) = new(refuse, script || ->(*) {}).tap(&:start)

  def initialize(refuse, script)
    @refuse = refuse
    @script = script
    @received = []
    @lock = Mutex.new
  end

  def start
    tcp = TCPServer.new('127.0.0.1', 0)
    @port = tcp.addr[1]
    @server = OpenSSL::SSL::SSLServer.new(tcp, context)
    @thread = Thread.new { serve(@server.accept) }
  end

  def url = "wss://127.0.0.1:#{@port}"

  def received = @lock.synchronize { @received.dup }

  def wait_for(count, seconds: 5)
    deadline = Time.now + seconds
    sleep 0.01 while received.size < count && Time.now < deadline
    received
  end

  def say(type, payload)
    @driver.text(JSON.generate(messageType: type, messagePayload: Base64.strict_encode64(JSON.generate(payload))))
  end

  def hang_up = @driver.close

  def drop = @socket.close

  def close
    @server.close
    @thread.kill
  end

  private

  def serve(socket)
    @socket = socket
    return refused(socket) if @refuse

    @driver = WebSocket::Driver.server(Wire.new(socket))
    listen
    loop { @driver.parse(socket.readpartial(16_384)) }
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  end

  def listen
    @driver.on(:connect) { @driver.start.tap { @query = URI.decode_www_form(@driver.env['QUERY_STRING']).to_h } }
    @driver.on(:open) { @script.call(:open, self) }
    @driver.on(:message) do |event|
      message = JSON.parse(event.data)
      @lock.synchronize { @received << message }
      @script.call(message, self)
    end
  end

  def refused(socket)
    socket.gets("\r\n\r\n")
    socket.write("HTTP/1.1 #{@refuse} Refused\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    socket.close
  end

  def context
    ca_key = OpenSSL::PKey::EC.generate('prime256v1')
    ca = certificate("/CN=Fake Kinesis Video #{SecureRandom.hex(4)}", ca_key, nil, ca_key)
    OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.add_cert(ca)
    key = OpenSSL::PKey::EC.generate('prime256v1')
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = leaf(key, ca, ca_key)
      context.key = key
    end
  end

  def leaf(key, authority, authority_key)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(1 << 64)
    cert.subject = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
    cert.issuer = authority.subject
    cert.public_key = key
    names = OpenSSL::X509::ExtensionFactory.new(authority, cert).create_extension('subjectAltName', 'IP:127.0.0.1')
    cert.add_extension(names)
    sign(cert, authority, authority_key)
  end
end
