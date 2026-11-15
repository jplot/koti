# frozen_string_literal: true

RSpec.describe Miele::Sdk::Cloud::Websocket do
  subject(:websocket) do
    described_class.new(session, follow: -> { channel.devices.map { "/Devices/#{it.fab}/State" } },
                                 sleeper: ->(seconds) { raise 'reconnecting again' if (waits << seconds).size > 2 })
  end

  let(:fake) { FakeWebsocket.start { |_connection, _index| nil } }
  let(:session) do
    organization = instance_double(Miele::Sdk::Cloud::Locales::Organization, rest: fake.url.sub('ws', 'http'))
    token = Miele::Sdk::Cloud::Token.new(value: 'one', refresh: nil, scheme: 'Bearer', created_at: 0, expires_at: 1)
    instance_double(Miele::Sdk::Cloud::Session, current: token, language: 'en-FR', organization:)
  end
  let(:cloud) { FakeCloud.start { |request| [403, {}, ''] if request.path == '/V2/Devices' } }
  let(:channel) do
    organization = Miele::Sdk::Cloud::Locales::Organization.new(iso: 'FR', rest: cloud.url, ciam: false,
                                                                ciam_endpoints: {})
    Miele::Sdk::Cloud::Channel.new(Miele::Sdk::Cloud::Session.new(organization))
  end
  let(:waits) { [] }

  before do
    Miele::Sdk.configure do |config|
      config.email = 'koti@example.com'
      config.password = 'secret'
    end
  end

  after do
    fake.stop
    cloud.stop
  end

  it 'ends the stream once the cloud refuses the appliance list, as the app stops observing it', :aggregate_failures do
    expect { websocket.each { nil } }.to raise_error(Miele::Sdk::AuthenticationError)
    expect(cloud.requests.map(&:path).tally).to eq('/V3/Login?org=FR' => 1, '/V2/Devices' => 1, '/V2/Logout' => 1)
  end
end
