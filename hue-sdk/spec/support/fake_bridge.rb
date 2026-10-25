# frozen_string_literal: true

require 'openssl'
require 'socket'
require 'tempfile'
require_relative 'test_certificates'

# HTTPS server standing in for a Hue bridge. Its certificates are minted per
# instance by a test CA, so the SDK's CA pinning and CN check run for real.
class FakeBridge
  include TestCertificates

  Request = Data.define(:verb, :path, :headers, :body)

  attr_reader :port, :ca_file

  def self.start(bridge_id: 'ECB5FAFFFE000001', foreign_ca: false, &handler)
    new(bridge_id:, foreign_ca:, handler: handler || ->(_request) { [200, {}, 'ok'] }).tap(&:start)
  end

  # Answers "VERB /path" from +routes+ (a payload, or [status, payload]) and 404 otherwise.
  def self.serving(routes)
    start do |request|
      status, payload = routes.fetch("#{request.verb} #{request.path}") { [404, { errors: [], data: [] }] }
                              .then { |route| route.is_a?(Array) ? route : [200, route] }
      [status, { 'Content-Type' => 'application/json' }, JSON.generate(payload)]
    end
  end

  def initialize(bridge_id:, foreign_ca:, handler:)
    @handler = handler
    @requests = []
    @clients = []
    @mutex = Mutex.new
    ca_cert, ca_key = certificate_authority
    signer_cert, signer_key = foreign_ca ? certificate_authority : [ca_cert, ca_key]
    @leaf_key = OpenSSL::PKey::EC.generate('prime256v1')
    @leaf = certificate("/C=NL/O=Philips Hue/OU=BSB003/CN=#{bridge_id}", @leaf_key, signer_cert, signer_key)
    @ca_file = Tempfile.create(%w[root-bridge .pem]).tap { |file| file.write(ca_cert.to_pem) }.tap(&:close).path
  end

  def start
    tcp = TCPServer.new('127.0.0.1', @port || 0)
    @port = tcp.addr[1]
    @server = OpenSSL::SSL::SSLServer.new(tcp, server_context)
    @server.start_immediately = false
    @acceptor = Thread.new { accept_loop }
  end

  def requests = @mutex.synchronize { @requests.dup }

  def connections = @mutex.synchronize { @clients.size }

  def down!
    @server.close
    [@acceptor, *@mutex.synchronize { @clients }].each(&:kill)
  end

  def up! = start

  def stop
    down!
    File.delete(@ca_file)
  end

  private

  def accept_loop
    loop do
      socket = @server.accept
      @mutex.synchronize { @clients << Thread.new { serve(socket) } }
    end
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  end

  def serve(socket)
    socket.accept
    while (request = read_request(socket))
      @mutex.synchronize { @requests << request }
      respond(socket, request)
    end
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  ensure
    socket.close unless socket.closed?
  end

  # A handler answering [status, headers, body, :cut] announces one byte more than it sends, then
  # drops TCP without TLS close_notify.
  def respond(socket, request)
    status, headers, body, cut = @handler.call(request)
    write_response(socket, status, headers, body, extra: cut ? 1 : 0)
    socket.io.close if cut
  end

  def read_request(socket)
    line = socket.gets("\r\n") or return
    verb, path = line.split
    headers = {}
    while (header = socket.gets("\r\n")) && header != "\r\n"
      name, value = header.chomp("\r\n").split(': ', 2)
      headers[name.downcase] = value
    end
    body = socket.read(Integer(headers['content-length'])) if headers['content-length']
    Request.new(verb:, path:, headers:, body:)
  end

  def write_response(socket, status, headers, body, extra: 0)
    lines = ["HTTP/1.1 #{status} Fake", "Content-Length: #{body.to_s.bytesize + extra}"]
    lines.concat(headers.map { |name, value| "#{name}: #{value}" })
    socket.write("#{lines.join("\r\n")}\r\n\r\n#{body}")
  end

  def server_context
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = @leaf
      context.key = @leaf_key
    end
  end
end
