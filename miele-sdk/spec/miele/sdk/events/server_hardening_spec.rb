# frozen_string_literal: true

require 'rbconfig'

RSpec.describe Miele::Sdk::Events::Server do
  subject(:server) { described_class.new(port: 0, fab: '000000004321') { nil } }

  before do
    Miele::Sdk.configure do |config|
      config.group_id = FakeAppliance::GROUP_ID
      config.group_key = FakeAppliance::GROUP_KEY
      config.read_timeout = 0.3
    end
    server.start
  end

  after { server.stop }

  def exchange(text)
    socket = TCPSocket.new('127.0.0.1', server.port)
    socket.write(text)
    socket.read if socket.wait_readable(2)
  ensure
    socket&.close
  end

  def push_request(authorization, length: 16, header: '')
    "POST /Devices/000000004321/SuperVision/000111222333/State/ HTTP/1.1\r\nHost: 127.0.0.1\r\n" \
      "Authorization: #{authorization}\r\nContent-Length: #{length}\r\n#{header}\r\n#{'x' * 16}"
  end

  it 'answers 403 to a signature that is not 32 bytes' do
    expect(exchange(push_request("MieleH256 #{FakeAppliance::GROUP_ID}:AB"))).to start_with('HTTP/1.1 403')
  end

  it 'answers 400 to a Content-Length out of range' do
    expect([-1, 1_000_000].map { exchange(push_request('x', length: it)).to_s[0, 12] }).to eq(['HTTP/1.1 400'] * 2)
  end

  it 'answers 400 to an overlong header line' do
    expect(exchange(push_request('x', header: "X-Long: #{'a' * 10_000}\r\n"))).to start_with('HTTP/1.1 400')
  end

  it 'closes a connection that stays silent past the read timeout' do
    socket = TCPSocket.new('127.0.0.1', server.port)
    expect(socket.wait_readable(2) && socket.read).to eq('')
  ensure
    socket&.close
  end

  it 'closes the connections it serves when stopped' do
    Miele::Sdk.config.read_timeout = 5
    socket = TCPSocket.new('127.0.0.1', server.port)
    socket.write("GET /Devices/ HTTP/1.1\r\n")
    sleep 0.2
    server.stop
    expect(socket.wait_readable(1) && socket.read).to eq('')
  ensure
    socket&.close
  end

  def spawn_starved_server
    env = { 'MIELE_GROUP_ID' => FakeAppliance::GROUP_ID, 'MIELE_GROUP_KEY' => FakeAppliance::GROUP_KEY }
    command = [RbConfig.ruby, '-I', File.expand_path('../../../../lib', __dir__),
               File.expand_path('../../../fixtures/events_server.rb', __dir__)]
    IO.popen(env, command, rlimit_nofile: 48)
  end

  it 'answers again once it ran out of file descriptors' do
    child = spawn_starved_server
    port = Integer(child.gets)
    Array.new(64) { TCPSocket.new('127.0.0.1', port) }.tap { sleep 0.5 }.each(&:close)
    push = JSON.generate(Resource: '/State/', Content: { Status: 5 })
    expect(deliver(port, 'POST', '/Devices/000000004321/SuperVision/000111222333/State/', push).code).to eq('204')
  ensure
    Process.kill('KILL', child.pid) if child
    child&.close
  end
end
