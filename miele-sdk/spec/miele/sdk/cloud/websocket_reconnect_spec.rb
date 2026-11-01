# frozen_string_literal: true

RSpec.describe Miele::Sdk::Cloud::Websocket do
  subject(:websocket) do
    described_class.new(session, follow: -> { ['/Devices/000123456789/State'] },
                                 fetch: ->(path) { (fetched << path) && '{"Status":1}' },
                                 sleeper: ->(seconds) { waits << seconds })
  end

  let(:session) do
    organization = instance_double(Miele::Sdk::Cloud::Locales::Organization, rest: fake.url.sub('ws', 'http'))
    instance_double(Miele::Sdk::Cloud::Session, language: 'en-FR', organization:)
  end
  let(:fetched) { [] }
  let(:waits) { [] }
  let(:fake) { FakeWebsocket.start(&script) }
  let(:script) do
    lambda do |connection, index|
      connection.send_binary(message("CC#{index}", %({"Status":#{index + 4}})))
      connection.drop if index == 1
    end
  end

  before do
    allow(session).to receive(:current).and_return(token('one'), token('two'))
    allow(session).to receive(:renew).and_return(token('two'))
  end

  after { fake.stop }

  def message(header, body)
    "#{header}\r\n\r\nPUT /V2/Devices/000123456789/State HTTP/1.1\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def token(value) = Miele::Sdk::Cloud::Token.new(value:, refresh: nil, scheme: 'Bearer', created_at: 0, expires_at: 1)

  def first_messages(count)
    received = []
    websocket.each do |message|
      received << message
      break if received.size == count
    end
    received
  end

  it 'reconnects with a fresh token 6 s after the server drops the connection', :aggregate_failures do
    first_messages(4)
    expect(fake.connections.map { it.request[:headers]['authorization'] }).to eq(['Bearer one', 'Bearer two'])
    expect(waits).to eq([6])
  end

  context 'when the cloud refuses the token' do
    let(:fake) { FakeWebsocket.start(refuse: 1, &script) }

    it 'renews it and tries again 6 s later with the new one', :aggregate_failures do
      first_messages(2)
      expect(session).to have_received(:renew).with(token('one'))
      expect(fake.connections.map { it.request[:headers]['authorization'] }).to eq(['Bearer one', 'Bearer two'])
      expect(waits).to eq([6])
    end
  end

  it "tries again 6 s later when the cloud's name does not resolve", :aggregate_failures do
    calls = 0
    allow(Socket).to receive(:tcp).and_wrap_original do |tcp, *args, **options|
      raise Socket::ResolutionError, 'getaddrinfo: nodename nor servname provided' if (calls += 1) == 1

      tcp.call(*args, **options)
    end
    expect(first_messages(2).map(&:body)).to eq(['{"Status":1}', '{"Status":5}'])
    expect(waits).to eq([6])
  end

  it 'refetches the followed resources on each connection, once each, delivering them first', :aggregate_failures do
    received = first_messages(4)
    expect(fetched).to eq(['/Devices/000123456789/State'] * 2)
    expect(received.map(&:body)).to eq(['{"Status":1}', '{"Status":5}', '{"Status":1}', '{"Status":6}'])
    expect(received.map(&:path).uniq).to eq(['/V2/Devices/000123456789/State'])
  end

  context 'when the connection drops in the middle of a message' do
    let(:script) do
      lambda do |connection, index|
        bytes = message("CC#{index}", %({"Status":#{index + 4}}))
        index == 1 ? connection.send_binary(bytes[0, 30]) : connection.send_binary(bytes)
        connection.drop if index == 1
      end
    end

    it 'delivers no message twice and no part of the lost one' do
      expect(first_messages(3).map(&:body)).to eq(['{"Status":1}', '{"Status":1}', '{"Status":6}'])
    end
  end

  context 'when the cloud sends nothing for a minute' do
    subject(:websocket) do
      times = [0.0]
      described_class.new(session, clock: -> { times.shift || 61.0 }, sleeper: ->(seconds) { waits << seconds })
    end

    let(:script) { ->(connection, index) { connection.send_binary(message('CC2', '{"Status":6}')) if index == 2 } }

    it 'reconnects at once, as the library watchdog does', :aggregate_failures do
      expect(first_messages(1).map(&:body)).to eq(['{"Status":6}'])
      expect([fake.connections.size, waits]).to eq([2, []])
    end
  end

  context 'when a followed resource cannot be read' do
    subject(:websocket) do
      described_class.new(session, follow: -> { %w[/Devices/1/State /Devices/2/State] },
                                   fetch: lambda { |path|
                                     raise Miele::Sdk::NotFoundError.new(404, 'gone') if path.include?('/1/')

                                     '{"Status":2}'
                                   })
    end

    it 'leaves it out and reads the others, as the app does' do
      expect(first_messages(2).map(&:path)).to eq(%w[/V2/Devices/2/State /V2/Devices/000123456789/State])
    end
  end

  context 'when the connection stays up' do
    let(:script) { ->(connection, _index) { connection.send_binary(message('CC1', '{"Status":5}')) } }

    it 'closes the socket and stops its threads when the block breaks', :aggregate_failures do
      threads = Thread.list
      first_messages(2)
      left = Thread.list - threads
      fake.stop
      expect(fake.connections.first.frames.map(&:opcode)).to eq([1, 8])
      expect(left).to be_empty
    end
  end
end
