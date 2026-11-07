# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Follow do
  include_context 'with the Hue cloud'

  let(:broker) { FakeMqtt.start(**broker_options) }
  let(:broker_options) { {} }
  let(:schema) { Hue::Sdk::Secure::Schema }

  before do
    Hue::Sdk::Secure.configure do |config|
      config.mqtt_host = 'localhost'
      config.mqtt_port = broker.port
      config.mqtt_ca_file = broker.ca_file
    end
  end

  after { broker.stop }

  def follow(topics: described_class::TOPICS)
    messages = []
    home.follow(topics:) { messages << it }
    messages
  end

  def string(body, at)
    length = body.byteslice(at, 2).unpack1('n')
    [body.byteslice(at + 2, length), at + 2 + length]
  end

  it 'offers ALPN mqtt and connects in MQTT 3.1.1 with the custom authorizer username', :aggregate_failures do
    follow
    body = broker.connect.body
    name, at = string(body, 0)
    client_id, at = string(body, at + 4)
    expect([broker.offered, name, body.getbyte(6), body.getbyte(7)]).to eq([%w[mqtt], 'MQTT', 4, 0x82])
    expect(client_id).to match(/\Ahue-sdk:\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(string(body, at).first).to eq('app?x-amz-customauthorizer-name=mqtt-app-authorizer&token=jwt-1')
  end

  it 'subscribes under dt:home/<home>/ and never publishes', :aggregate_failures do
    follow(topics: %w[arm/state timeline/update])
    subscribe = broker.packets.find { it.type == 8 }.body
    first, at = string(subscribe, 2)
    expect([first, string(subscribe, at + 1).first]).to eq(%w[dt:home/home-1/arm/state dt:home/home-1/timeline/update])
    expect(broker.packets.map(&:type)).not_to include(3)
  end

  context 'when the broker publishes' do
    let(:broker_options) do
      { publishes: [['dt:home/home-1/arm/state', JSON.generate('arm_state' => 'armed_away', 'trigger_time' => 't',
                                                               'apply_time' => 'a', 'source' => { 'type' => 'user',
                                                                                                  'id' => 'u' })],
                    ['dt:home/home-1/device/cam-1/config', JSON.generate('enabled' => true)],
                    ['dt:home/home-1/arm/config', 'null'], ['dt:home/home-1/other', '{not json']] }
    end

    it 'yields a typed value by topic, and returns when the broker ends the connection', :aggregate_failures do
      messages = follow
      expect(messages.map(&:topic)).to eq(%w[arm/state device/cam-1/config arm/config other])
      expect(messages[0].attributes.arm_state).to eq('armed_away')
      expect(messages[1].attributes).to be_a(schema::CameraConfigUpdateEventValues)
    end

    it 'leaves the payload of a topic it cannot read' do
      expect(follow.drop(2).map { [it.attributes, it.payload] }).to eq([[nil, 'null'], [nil, '{not json']])
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
    let(:broker_options) { { connack: 5 } }

    it 'raises AuthenticationError, without the token' do
      expect { follow }.to raise_error(Hue::Sdk::AuthenticationError, satisfy { !it.include?('jwt-1') })
    end
  end

  context 'when the broker drops the connection before answering' do
    let(:broker_options) { { connack: :drop } }

    it 'raises ConnectionError, without the token' do
      expect { follow }.to raise_error(Hue::Sdk::ConnectionError, satisfy { !it.include?('jwt-1') })
    end
  end

  it 'trusts only the pinned root' do
    Hue::Sdk::Secure.configure { it.mqtt_ca_file = FakeMqtt.new(0, []).tap(&:start).ca_file }
    expect { follow }.to raise_error(Hue::Sdk::TLSError)
  end
end
