# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) do
    described_class.new('127.0.0.1', fab:, clock: -> { cloud.requests.size * 2.0 }, cloud: channel)
  end

  let(:fab) { '000123456789' }
  let(:cloud) do
    FakeCloud.start do |request|
      case request.path
      when '/V2/AppTokenRefresh' then FakeCloud.json(appToken: 'token-2', appTokenValidity: Time.now.to_i + 3600)
      when %r{\A/V2/Devices/} then [204, {}, '']
      end
    end
  end
  let(:later) { [0] }
  let(:channel) do
    ahead = later
    session = Miele::Sdk::Cloud::Session.new(Miele::Sdk::Cloud::Locales.organization('FR'),
                                             clock: -> { Time.now + ahead.first })
    Miele::Sdk::Cloud::Channel.new(session)
  end

  before do
    Miele::Sdk.configure do |config|
      config.email = 'koti@example.com'
      config.password = 'secret'
      config.locales_host = cloud.url
      config.read_timeout = 30
    end
  end

  after { cloud.stop }

  it 'counts the login a rename makes in its 15 s before taking what they leave' do
    timeouts = read_timeouts
    appliance.name = 'Cuisine'
    expect(timeouts.last).to eq(13)
  end

  it 'counts the renewal a rename makes in its 15 s before taking what they leave' do
    channel.session.current
    later[0] = 7200
    timeouts = read_timeouts
    appliance.name = 'Cuisine'
    expect(timeouts.last).to eq(13)
  end
end
