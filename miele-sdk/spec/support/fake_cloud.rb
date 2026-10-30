# frozen_string_literal: true

require 'json'
require 'socket'

# Plain-HTTP server standing in for the Miele cloud. It answers the locales and the MCS login of France
# unless the spec's handler answers first, and keeps every request it receives.
class FakeCloud
  Request = Data.define(:verb, :path, :headers, :body)

  attr_reader :port

  def self.start(&handler) = new(handler || ->(_request) {}).tap(&:start)

  def initialize(handler)
    @handler = handler
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

  def self.json(value, status = 200) = [status, { 'Content-Type' => 'application/json' }, JSON.generate(value)]

  private

  def accept_loop
    loop { serve(@server.accept) }
  rescue IOError
    nil
  end

  def serve(socket)
    request = read_request(socket)
    @mutex.synchronize { @requests << request }
    status, headers, body = @handler.call(request) || answer(request)
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
    case request.path
    when '/V3/Locales/Countries' then FakeCloud.json([{ organization: { iso: 'FR' }, countries: [{ iso: 'FR' }] }])
    when '/V3/Locales?org=FR' then FakeCloud.json([sales_company])
    when '/V3/Login?org=FR' then FakeCloud.json(appToken: 'token-1', appTokenValidity: Time.now.to_i + 3600)
    else [404, {}, '']
    end
  end

  def sales_company
    { organization: { iso: 'FR' }, countries: [{ iso: 'FR' }],
      mcsConfig: { dnsNames: [{ type: 'api', host: 'api.example.com' }, { type: 'rest', host: url }] },
      ciam: { active: false, endpoints: [] }, features: [{ name: 'shop', config: [{ key: 'apiKey', value: 'x' }] }] }
  end
end
