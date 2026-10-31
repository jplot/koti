# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Miele::Sdk do
  let(:cloud) do
    FakeCloud.start(threaded: true) do |request|
      next unless request.path == '/V2/AppTokenRefresh'

      FakeCloud.json(appToken: 'renewed', appTokenValidity: Time.now.to_i + 3600)
    end
  end
  let(:token_file) { File.join(Dir.mktmpdir, 'token.json') }

  before do
    described_class.configure do |config|
      config.country = 'FR'
      config.locales_host = cloud.url
      config.token_file = token_file
    end
  end

  after { cloud.stop }

  def save(scheme, created_at)
    token = Miele::Sdk::Cloud::Token.new(value: 'saved', refresh: 'saved', scheme:, created_at:,
                                         expires_at: Time.now + 600)
    File.write(token_file, token.to_json)
  end

  it 'renews once when several threads first reach the cloud with a due saved token' do
    save('appToken', Time.now - 3000)
    described_class.configure { it.email = 'koti@example.com' }
    Array.new(8) { Thread.new { described_class.cloud.session.authorization } }.each(&:join)
    expect(cloud.requests.count { it.path == '/V2/AppTokenRefresh' }).to eq(1)
  end

  it 'opens the cloud of an account kept in token_file, without an e-mail' do
    save('Bearer', Time.now)
    expect(described_class.cloud.session.token.value).to eq('saved')
  end

  it 'does not keep a cloud built from the copy of the app', :aggregate_failures do
    save('Bearer', Time.now)
    described_class.configure { it.locales_host = 'http://127.0.0.1:9' }
    first = described_class.cloud
    expect(first.session.organization.bundled).to be(true)
    expect(described_class.cloud).not_to equal(first)
  end
end
