# frozen_string_literal: true

RSpec.describe Miele::Sdk::Events::CloudStream do
  subject(:stream) { described_class.new(channel) }

  let(:pushes) { [] }
  let(:fake) do
    sent = pushes
    FakeWebsocket.start { |connection, _index| sent.each { connection.send_binary(it) } }
  end
  let(:devices) { [] }
  let(:channel) do
    organization = instance_double(Miele::Sdk::Cloud::Locales::Organization, rest: fake.url.sub('ws', 'http'))
    token = Miele::Sdk::Cloud::Token.new(value: 'token', refresh: nil, scheme: 'Bearer', created_at: 0, expires_at: 1)
    session = instance_double(Miele::Sdk::Cloud::Session, current: token, language: 'en-FR', organization:)
    instance_double(Miele::Sdk::Cloud::Channel, session:, devices:)
  end

  after { fake.stop }

  def push(path, body) = "CC\r\n\r\nPUT #{path} HTTP/1.1\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"

  def first_events(count)
    received = []
    stream.each do |event|
      received << event
      break if received.size == count
    end
    received
  end

  def event(fab, resource, content) = Miele::Sdk::Events::Event.new(fab:, resource:, content:, source: :cloud)

  it 'reaches the cloud only once it connects' do
    allow(channel).to receive(:devices).and_raise(Miele::Sdk::ConnectionError, 'offline')
    expect { stream }.not_to raise_error
  end

  it 'streams a cloud State change as an event' do
    pushes << push('/V2/Devices/000123456789/State', '{"Status":5}')
    expect(first_events(1)).to eq([event('000123456789', '/State/', { 'Status' => 5 })])
  end

  it 'streams an Ident change, keeping a mac id as it is' do
    pushes << push('/V2/Devices/mac-00A0B1C2D3E4/Ident', '{"DeviceType":21}')
    expect(first_events(1)).to eq([event('mac-00A0B1C2D3E4', '/Ident/', { 'DeviceType' => 21 })])
  end

  it 'decodes a pushed DOP2 leaf' do
    leaf = Miele::Sdk::Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                                      fields: { 1 => Miele::Sdk::Dop2::Field.new(type: :e8, value: 4) })
    pushes << push('/V2/Devices/000123456789/DOP2/2/1586', Miele::Sdk::Dop2.encode(leaf))
    expect(first_events(1)).to eq([event('000123456789', '/DOP2/2/1586/', leaf)])
  end

  it 'skips a resource the app does not read from the websocket' do
    pushes << push('/V2/Devices/000123456789/Statistics', '{}') << push('/V2/Devices/000123456789/State', '{}')
    expect(first_events(1).map(&:resource)).to eq(['/State/'])
  end

  it 'streams the list of devices' do
    pushes << push('/V2/Devices', '[{"host":"Miele-1"}]')
    expect(first_events(1)).to eq([event(nil, '/Devices/', [{ 'host' => 'Miele-1' }])])
  end

  context 'with appliances on the account' do
    let(:devices) { [Miele::Sdk::Cloud::Channel::Device.new(fab: '000123456789', host: 'h', ident: {}, state: {})] }

    it 'reads the State of each on connecting, as the app does' do
      answer = Miele::Sdk::Connection::Response.new(status: 200, body: '{"Status":1}')
      allow(channel).to receive(:request).with(:get, '/Devices/000123456789/State').and_return(answer)
      expect(first_events(1)).to eq([event('000123456789', '/State/', { 'Status' => 1 })])
    end
  end
end
