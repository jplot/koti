# frozen_string_literal: true

RSpec.describe Miele::Sdk::Cloud::Websocket do
  subject(:websocket) { described_class.new(session) }

  let(:session) do
    organization = instance_double(Miele::Sdk::Cloud::Locales::Organization, rest: fake.url.sub('ws', 'http'))
    instance_double(Miele::Sdk::Cloud::Session, authorization: 'Bearer token', language: 'en-FR', organization:)
  end
  let(:fake) { FakeWebsocket.start(&script) }
  let(:script) { ->(connection, _index) { connection.send_binary(message('CC1', '{"Status":5}')) } }

  after { fake.stop }

  def message(header, body, path: '/V2/Devices/000123456789/State')
    "#{header}\r\n\r\nPUT #{path} HTTP/1.1\r\nContent-Type: application/json\r\n" \
      "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def first_messages(count)
    received = []
    websocket.each do |message|
      received << message
      break if received.size == count
    end
    received
  end

  it "connects with the app's headers and sub-protocol", :aggregate_failures do
    first_messages(1)
    request = fake.connections.first.request
    expect(request[:line]).to eq('GET /websocket/V2/Devices/ HTTP/1.1')
    expect(request[:headers]).to include('authorization' => 'Bearer token', 'accept-language' => 'en-FR',
                                         'sec-websocket-protocol' => 'mielecloudconnect', 'upgrade' => 'websocket',
                                         'sec-websocket-version' => '13')
  end

  it 'parses a message into its path, headers and body' do
    expect(first_messages(1)).to eq([described_class::Message.new(
      path: '/V2/Devices/000123456789/State',
      headers: { 'Content-Type' => 'application/json', 'Content-Length' => '12' }, body: '{"Status":5}'
    )])
  end

  context 'when a message comes split across frames' do
    let(:script) do
      lambda do |connection, _index|
        bytes = message('CC1', '{"Status":5}')
        connection.send_binary(bytes[0, 20])
        connection.send_binary(bytes[20..])
      end
    end

    it 'parses it once it is whole' do
      expect(first_messages(1).map(&:body)).to eq(['{"Status":5}'])
    end
  end

  context 'when a frame holds more than 125 bytes' do
    let(:script) { ->(connection, _index) { connection.send_binary(message('CC1', "\"#{'x' * 300}\"")) } }

    it 'reads its two-byte length' do
      expect(first_messages(1).first.body.bytesize).to eq(302)
    end
  end

  context 'when two messages come in one frame' do
    let(:script) do
      ->(connection, _index) { connection.send_binary(message('CC1', '{"Status":5}') + message('CC2', '{"Status":1}')) }
    end

    it 'parses both' do
      expect(first_messages(2).map(&:body)).to eq(['{"Status":5}', '{"Status":1}'])
    end
  end

  it 'acknowledges each message with its CloudConnectHeader, as the app does' do
    first_messages(1)
    fake.stop
    acks = fake.connections.first.frames.reject { it.opcode == 8 }.map(&:payload)
    expect(acks).to eq(["CC1\r\n\r\nHTTP/1.1 204 No Content\r\n\r\n"])
  end

  context 'when the cloud pings' do
    let(:script) do
      lambda do |connection, _index|
        connection.send_ping('hello')
        connection.send_binary(message('CC1', '{"Status":5}'))
      end
    end

    it 'answers a ping with a pong' do
      first_messages(1)
      fake.stop
      expect(fake.connections.first.frames.find { it.opcode == 10 }&.payload).to eq('hello')
    end
  end

  context 'when the cloud sends nothing for a while' do
    subject(:websocket) do
      times = [0.0]
      described_class.new(session, clock: -> { times.shift || 45.0 })
    end

    let(:script) do
      lambda do |connection, _index|
        sleep 0.3
        connection.send_binary(message('CC1', '{"Status":5}'))
      end
    end

    it 'keeps the connection alive with an unsolicited pong every 30 s, as .NET does' do
      first_messages(1)
      fake.stop
      expect(fake.connections.first.frames.select { it.opcode == 10 }.map(&:payload)).to eq([''])
    end
  end

  context 'when the cloud answers the handshake with another key' do
    subject(:websocket) do
      described_class.new(session, sleeper: ->(_seconds) { raise stop })
    end

    let(:fake) { FakeWebsocket.start(accept: 'wrong', &script) }
    let(:stop) { Class.new(StandardError) }

    it 'tries again 6 s later, as the app does' do
      expect { first_messages(1) }.to raise_error(stop)
    end
  end
end
