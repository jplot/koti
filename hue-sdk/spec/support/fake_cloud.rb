# frozen_string_literal: true

require 'json'
require 'socket'

# Plain-HTTP server standing in for the Hue account's cloud. It answers the OpenID discovery unless the spec's
# handler answers first, closes the connection without an answer when the handler returns :drop, and keeps every
# request it receives.
class FakeCloud
  Request = Data.define(:verb, :path, :headers, :body) do
    def form = URI.decode_www_form(body).to_h
  end

  attr_reader :port

  def self.start(threaded: false, &handler) = new(handler || ->(_request) {}, threaded:).tap(&:start)

  def self.json(value, status = 200, headers = {})
    [status, { 'Content-Type' => 'application/json', **headers }, JSON.generate(value)]
  end

  def initialize(handler, threaded:)
    @handler = handler
    @threaded = threaded
    @requests = []
    @mutex = Mutex.new
  end

  def start
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @acceptor = Thread.new { accept_loop }
  end

  def url = "http://127.0.0.1:#{port}"

  def requests = @mutex.synchronize { @requests.dup }

  def stop
    @server.close
    @acceptor.kill
  end

  private

  def accept_loop
    loop do
      socket = @server.accept
      @threaded ? Thread.new { serve(socket) } : serve(socket)
    end
  rescue IOError
    nil
  end

  def serve(socket)
    request = read_request(socket)
    @mutex.synchronize { @requests << request }
    answer = @handler.call(request) || answer(request)
    return if answer == :drop

    status, headers, body = answer
    lines = ["HTTP/1.1 #{status} Fake", "Content-Length: #{body.bytesize}",
             *headers.map { |name, value| "#{name}: #{value}" }]
    socket.write("#{lines.join("\r\n")}\r\n\r\n#{body}")
  ensure
    socket.close
  end

  def read_request(socket)
    verb, path = socket.gets("\r\n").split
    headers = {}
    while (line = socket.gets("\r\n")) != "\r\n"
      name, value = line.chomp("\r\n").split(': ', 2)
      headers[name.downcase] = value
    end
    Request.new(verb:, path:, headers:, body: socket.read(Integer(headers.fetch('content-length', '0'))))
  end

  def answer(request)
    return [404, {}, ''] unless request.path == '/.well-known/openid-configuration'

    FakeCloud.json(authorization_endpoint: "#{url}/authorize", token_endpoint: "#{url}/oauth/token")
  end
end
