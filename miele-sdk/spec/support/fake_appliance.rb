# frozen_string_literal: true

require 'socket'
require 'time'

# Plain-HTTP server standing in for a Miele appliance: it checks the MieleH256
# signature of each request, decrypts its body, then encrypts and signs its
# answers with Miele::Sdk::Crypto, so the SDK's transport runs for real.
class FakeAppliance
  GROUP_ID = '0123456789ABCDEF'
  GROUP_KEY = (0..63).to_a.pack('C*').unpack1('H*').upcase
  CONTENT_TYPE = 'application/vnd.miele.v1+json; charset=utf-8'

  Request = Data.define(:verb, :path, :headers, :body, :verified)

  attr_reader :port

  def self.start(answer_key: GROUP_KEY, unsigned: false, &handler)
    new(answer_key:, unsigned:, handler: handler || ->(_request) { [200, {}, '{}'] }).tap(&:start)
  end

  def initialize(answer_key:, unsigned:, handler:)
    @answer_key = [answer_key].pack('H*')
    @unsigned = unsigned
    @handler = handler
    @requests = []
    @mutex = Mutex.new
  end

  def start
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @acceptor = Thread.new { accept_loop }
  end

  def requests = @mutex.synchronize { @requests.dup }

  def stop
    @server.close
    @acceptor.kill
  end

  private

  def key = [GROUP_KEY].pack('H*')

  def accept_loop
    loop { serve(@server.accept) }
  rescue IOError
    nil
  end

  def serve(socket)
    request = read_request(socket)
    @mutex.synchronize { @requests << request }
    status, headers, plaintext = @handler.call(request)
    write_response(socket, status, headers, plaintext.to_s)
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
    cipher = socket.read(Integer(headers.fetch('content-length', '0')))
    decode(verb, path, headers, cipher)
  end

  def decode(verb, path, headers, cipher)
    signature = [headers.fetch('authorization', ':').split(':', 2).last].pack('H*')
    body = cipher.empty? ? '' : Miele::Sdk::Crypto.decrypt(key:, signature:, ciphertext: cipher)
    lines = [verb, "#{headers['host']}#{path}", headers.fetch('content-type', ''), headers['accept'], headers['date']]
    verified = Miele::Sdk::Crypto.signature(key:, lines:, body:) == signature
    Request.new(verb:, path:, headers:, body: unpadded(body, path), verified:)
  end

  # A DOP2 body ends where its size says: its last bytes may be NULs, which rstrip would take for padding.
  def unpadded(body, path)
    return body.rstrip unless path.include?('/DOP2/') && body.bytesize >= 2

    body.byteslice(0, 2 + body.unpack1('n'))
  end

  def write_response(socket, status, headers, plaintext)
    date = Time.now.httpdate
    lines = ["HTTP/1.1 #{status} Fake", "Date: #{date}", "Content-Type: #{CONTENT_TYPE}"]
    body = plaintext.empty? || @unsigned ? plaintext : sign_and_encrypt(lines, status, date, plaintext)
    lines << "Content-Length: #{body.bytesize}"
    lines.concat(headers.map { |name, value| "#{name}: #{value}" })
    socket.write("#{lines.join("\r\n")}\r\n\r\n#{body}")
  end

  def sign_and_encrypt(lines, status, date, plaintext)
    padded = Miele::Sdk::Crypto.pad(plaintext)
    signature = Miele::Sdk::Crypto.signature(key: @answer_key, lines: [status, CONTENT_TYPE, date], body: padded)
    lines << "X-Signature: #{Miele::Sdk::Crypto.authorization(group_id: [GROUP_ID].pack('H*'), signature:)}"
    Miele::Sdk::Crypto.encrypt(key: @answer_key, signature:, plaintext: padded)
  end
end
