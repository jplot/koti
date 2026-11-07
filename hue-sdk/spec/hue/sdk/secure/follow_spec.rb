# frozen_string_literal: true

require 'open3'

RSpec.describe Hue::Sdk::Secure::Follow do
  include_context 'with the Hue cloud'

  let(:broker) { FakeMqtt.start }
  let(:schema) { Hue::Sdk::Secure::Schema }

  before do
    Hue::Sdk::Secure.configure do |config|
      config.mqtt_host = 'localhost'
      config.mqtt_port = broker.port
      config.mqtt_ca_file = broker.ca_file
    end
  end

  after { broker.stop }

  def follow(topics: described_class::TOPICS, keep_alive: 60) = described_class.new('home-1', topics:, keep_alive:).to_a

  def fail_in_block = raise(IOError, 'caller')

  def string(body, at)
    length = body.byteslice(at, 2).unpack1('n')
    [body.byteslice(at + 2, length), at + 2 + length]
  end

  def types = broker.packets.map(&:type)

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  it 'offers ALPN mqtt and connects in MQTT 3.1.1 with the custom authorizer username', :aggregate_failures do
    follow
    body = broker.connect.body
    name, at = string(body, 0)
    client_id, at = string(body, at + 4)
    expect([broker.offered, name, body.getbyte(6), body.getbyte(7)]).to eq([%w[mqtt], 'MQTT', 4, 0x82])
    expect(client_id).to match(/\Ahue-sdk:\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(string(body, at).first).to eq('app?x-amz-customauthorizer-name=mqtt-app-authorizer&token=jwt-1')
  end

  it 'subscribes under dt:home/<home>/ at QoS 1, as the app does, and never publishes', :aggregate_failures do
    follow(topics: %w[arm/state timeline/update])
    subscribe = broker.packets.find { it.type == 8 }.body
    first, at = string(subscribe, 2)
    second, last = string(subscribe, at + 1)
    expect([first, subscribe.getbyte(at), second, subscribe.getbyte(last)])
      .to eq(['dt:home/home-1/arm/state', 1, 'dt:home/home-1/timeline/update', 1])
    expect(types).not_to include(3)
  end

  context 'when the broker ends the connection right after its last message' do
    def follow_burst
      burst = FakeMqtt.start do |fake, socket|
        socket.write(fake.suback)
        3.times { socket.write(fake.publish('dt:home/home-1/arm/state', 'null', id: 1)) }
      end
      Hue::Sdk::Secure.configure { it.mqtt_port = burst.port }
      Hue::Sdk::Secure.configure { it.mqtt_ca_file = burst.ca_file }
      follow.size
    ensure
      burst&.stop
    end

    # On 2026-11-08, 6 follows in 200 raised MQTT::NotConnectedException: the gem's reader thread had closed the socket
    # before the acknowledgement of the last message.
    it 'yields every message the gem read, however its two threads interleave' do
      expect(Array.new(200) { follow_burst }).to all(eq(3))
    end
  end

  context 'when the broker ends the connection while the block runs' do
    let(:broker) do
      FakeMqtt.start do |fake, socket|
        socket.write(fake.suback)
        socket.write(fake.publish('dt:home/home-1/arm/state', 'null', id: 1))
        sleep 0.1
        socket.write(fake.publish('dt:home/home-1/arm/state', 'null', id: 1))
      end
    end
    let(:follower) { described_class.new('home-1', topics: %w[arm/state]) }
    let(:seen) { [] }

    def stall(message) = seen.push(message) && sleep(0.3)

    it 'yields what is left once the block returns, and returns' do
      follower.each { stall(it) }
      expect(seen.size).to eq(2)
    end

    it 'lets the error of the block through, and yields no more', :aggregate_failures do
      expect { follower.each { stall(it) && fail_in_block } }.to raise_error(IOError, 'caller')
      expect(seen.size).to eq(1)
    end

    it 'yields no more after a break' do
      follower.find { stall(it) }
      expect(seen.size).to eq(1)
    end
  end

  context 'when the broker publishes and ends the connection' do
    let(:broker) do
      state = JSON.generate('arm_state' => 'armed_away', 'trigger_time' => 't', 'apply_time' => 'a',
                            'source' => { 'type' => 'user', 'id' => 'u' })
      FakeMqtt.start(publishes: [['dt:home/home-1/arm/state', state],
                                 ['dt:home/home-1/device/cam-1/config', JSON.generate('enabled' => true)],
                                 ['dt:home/home-1/arm/config', 'null'], ['dt:home/home-1/other', '{"été": 1']])
    end

    it 'yields a typed value by topic, and returns', :aggregate_failures do
      messages = follow
      expect(messages.map(&:topic)).to eq(%w[arm/state device/cam-1/config arm/config other])
      expect(messages[0].attributes.arm_state).to eq('armed_away')
      expect(messages[1].attributes).to be_a(schema::CameraConfigUpdateEventValues)
    end

    it 'leaves the payload of a topic it cannot read, in UTF-8' do
      expect(follow.drop(2).map { [it.attributes, it.payload, it.payload.encoding] })
        .to eq([[nil, 'null', Encoding::UTF_8], [nil, '{"été": 1', Encoding::UTF_8]])
    end

    it 'lets an error of the block through' do
      expect { described_class.new('home-1', topics: %w[arm/state]).each { fail_in_block } }
        .to raise_error(IOError, 'caller')
    end
  end

  context 'when the broker publishes and keeps the connection' do
    let(:broker) do
      FakeMqtt.start do |fake, socket|
        socket.write(fake.suback)
        socket.write(fake.publish('dt:home/home-1/arm/config', 'null', id: 7))
        socket.write(fake.publish('dt:home/home-1/arm/state', 'null'))
        fake.read(socket) while socket.wait_readable(3)
      end
    end

    it 'yields at once, acknowledges a QoS 1 message, and disconnects when the caller stops', :aggregate_failures do
      started = now
      seen = []
      described_class.new('home-1', topics: %w[arm/state]).each { break if (seen << it.topic).size == 2 }
      expect([seen, now - started < 1]).to eq([%w[arm/config arm/state], true])
      sleep 0.3
      expect(broker.packets.select { [4, 14].include?(it.type) }.map { [it.type, it.body] })
        .to eq([[4, "\x00\x07".b], [14, '']])
    end
  end

  context 'when messages keep coming' do
    let(:broker) do
      FakeMqtt.start do |fake, socket|
        socket.write(fake.suback)
        8.times do
          socket.write(fake.publish('dt:home/home-1/arm/state', 'null'))
          socket.write([0xd0, 0].pack('CC')) if socket.wait_readable(0.3) && fake.read(socket).type == 12
        end
      end
    end

    it 'still pings once the keep-alive has passed since it last sent' do
      follow(keep_alive: 1)
      expect(types).to include(12)
    end
  end

  context 'when a ping gets no answer' do
    let(:broker) do
      FakeMqtt.start do |fake, socket|
        socket.write(fake.suback)
        fake.read(socket) while socket.wait_readable(4)
      end
    end

    it 'raises ConnectionError' do
      expect { follow(keep_alive: 1) }.to raise_error(Hue::Sdk::ConnectionError, /ping/i)
    end
  end

  context 'when the broker drops the connection while following' do
    let(:broker) { FakeMqtt.start { |fake, socket| socket.write(fake.suback) && socket.to_io.close } }

    it 'raises ConnectionError, without the token' do
      expect { follow }.to raise_error(Hue::Sdk::ConnectionError, satisfy { !it.include?('jwt-1') })
    end
  end

  context 'when the token is due' do
    before do
      due = Hue::Sdk::Secure::Token.new(value: 'old', refresh: 'refresh-1', created_at: Time.now - 86_400,
                                        expires_at: Time.now + 20)
      Hue::Sdk::Secure.configure { it.token = due.to_json }
      answers.push(FakeCloud.json(access_token: 'renewed', refresh_token: 'refresh-2', expires_in: 86_400))
    end

    it 'renews it before connecting' do
      follow
      expect(broker.connect.body).to end_with('&token=renewed')
    end
  end

  context 'when the broker refuses the token' do
    let(:broker) { FakeMqtt.start(connack: 5) }

    it 'raises AuthenticationError, without the token' do
      expect { follow }.to raise_error(Hue::Sdk::AuthenticationError, satisfy { !it.include?('jwt-1') })
    end
  end

  context 'when the broker drops the connection before answering' do
    let(:broker) { FakeMqtt.start(connack: :drop) }

    it 'raises ConnectionError, without the token' do
      expect { follow }.to raise_error(Hue::Sdk::ConnectionError, satisfy { !it.include?('jwt-1') })
    end
  end

  context 'when the broker never answers the TLS handshake' do
    let(:silent) { TCPServer.new('127.0.0.1', 0) }

    before do
      Hue::Sdk::Secure.configure do |config|
        config.mqtt_port = silent.addr[1]
        config.open_timeout = 0.5
        config.read_timeout = 0.5
      end
    end

    after { silent.close }

    it 'raises ConnectionError after open_timeout and read_timeout' do
      expect { Timeout.timeout(3) { follow } }.to raise_error(Hue::Sdk::ConnectionError)
    end
  end

  describe 'without the mqtt gem' do
    it 'loads Hue Secure without it' do
      lib = File.expand_path('../../../../lib', __dir__)
      output, = Open3.capture2(RbConfig.ruby, '-I', lib, '-e', "require 'hue/sdk/secure'; print defined?(MQTT).inspect")
      expect(output).to eq('nil')
    end

    it 'asks for it when following' do
      follower = described_class.new('home-1', topics: %w[arm/state])
      allow(follower).to receive(:require).with('mqtt').and_raise(LoadError)
      expect { follower.each { nil } }.to raise_error(Hue::Sdk::Error, /gem 'mqtt'/)
    end
  end

  context 'with a certificate of another authority, or for another name' do
    let(:other) { FakeMqtt.start(name: 'other.example') }

    after { other.stop }

    it 'trusts only the pinned root' do
      Hue::Sdk::Secure.configure { it.mqtt_ca_file = other.ca_file }
      expect { follow }.to raise_error(Hue::Sdk::TLSError)
    end

    it 'checks the name of the broker' do
      Hue::Sdk::Secure.configure do |config|
        config.mqtt_port = other.port
        config.mqtt_ca_file = other.ca_file
      end
      expect { follow }.to raise_error(Hue::Sdk::TLSError, /hostname/)
    end
  end
end
