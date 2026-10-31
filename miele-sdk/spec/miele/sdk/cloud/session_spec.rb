# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Miele::Sdk::Cloud::Session do
  subject(:session) do
    described_class.new(organization, clock: -> { times.last }, sleeper: ->(seconds) { naps << seconds })
  end

  let(:now) { Time.at(Time.now.to_i) }
  let(:times) { [now] }
  let(:naps) { [] }
  let(:renewals) { [] }
  let(:cloud) do
    FakeCloud.start do |request|
      case request.path
      when '/V3/Login?org=FR' then FakeCloud.json(appToken: 'token-1', appTokenValidity: now.to_i + 100)
      when '/V2/AppTokenRefresh'
        renewals.shift || FakeCloud.json(appToken: 'renewed', appTokenValidity: now.to_i + 3600)
      when '/fr/token' then FakeCloud.json(access_token: 'jwt-1', refresh_token: 'refresh-1', expires_in: 3600)
      end
    end
  end

  before do
    Miele::Sdk.configure do |config|
      config.email = 'koti@example.com'
      config.password = 'secret'
    end
  end

  after { cloud.stop }

  def organization
    Miele::Sdk::Cloud::Locales::Organization.new(
      iso: 'FR', rest: cloud.url, ciam: false,
      ciam_endpoints: { 'authorize' => "#{cloud.url}/fr/authorize", 'token' => "#{cloud.url}/fr/token" }
    )
  end

  def posts(path) = cloud.requests.select { it.path == path }

  def half_life_later
    session.login
    times << (now + 60)
  end

  it 'logs in with e-mail and password and sends the appToken', :aggregate_failures do
    expect(session.authorization).to eq('appToken token-1')
    login = posts('/V3/Login?org=FR').first
    expect([login.verb, login.headers['content-type'], JSON.parse(login.body)])
      .to eq(['POST', 'application/json', { 'email' => 'koti@example.com', 'password' => 'secret' }])
  end

  context 'when the MCS token is past half its life' do
    before { half_life_later }

    it 'renews it with the appToken and an empty object', :aggregate_failures do
      expect(session.authorization).to eq('appToken renewed')
      renewal = posts('/V2/AppTokenRefresh').first
      expect([renewal.headers['authorization'], renewal.body]).to eq(['appToken token-1', '{}'])
    end

    it 'renews once when several threads find the same token expired' do
      Array.new(8) { Thread.new { session.authorization } }.each(&:join)
      expect(posts('/V2/AppTokenRefresh').size).to eq(1)
    end

    it 'tries a renewal three times, a second apart', :aggregate_failures do
      renewals.push([500, {}, ''], [500, {}, ''])
      expect(session.authorization).to eq('appToken renewed')
      expect([posts('/V2/AppTokenRefresh').size, naps]).to eq([3, [1, 1]])
    end

    it 'logs in again when the renewal is refused' do
      renewals.push([401, {}, ''])
      session.authorization
      expect(posts('/V3/Login?org=FR').size).to eq(2)
    end
  end

  it 'builds the CIAM authorize address' do
    Miele::Sdk.configure { it.ciam_client_id = 'com.example.app' }
    expect(session.authorize_url).to match(
      %r{\A#{cloud.url}/fr/authorize\?client_id=com\.example\.app&scope=openid\+bpdata\+mcs\+shop\+zuora
         &state=\h{2}(-\h{2}){15}&response_type=code&redirect_uri=miele%3A%2F%2Foauth2-code%2F\z}x
    )
  end

  it 'exchanges a CIAM code for a bearer token', :aggregate_failures do
    Miele::Sdk.configure { it.ciam_client_id = 'com.example.app' }
    session.exchange('code-1')
    expect(session.authorization).to eq('Bearer jwt-1')
    expect(URI.decode_www_form(posts('/fr/token').first.body).to_h).to eq(
      'grant_type' => 'authorization_code', 'code' => 'code-1', 'redirect_uri' => 'miele://oauth2-code/',
      'client_id' => 'com.example.app'
    )
  end

  it 'asks for a CIAM code instead of logging in where the country logs in through CIAM' do
    ciam = organization.with(ciam: true)
    expect { described_class.new(ciam).authorization }
      .to raise_error(Miele::Sdk::ConfigurationError, /authorize_url/)
  end

  it 'saves every new token to the token file and starts from it', :aggregate_failures do
    path = File.join(Dir.mktmpdir, 'token.json')
    Miele::Sdk.configure { it.token_file = path }
    session.authorization
    expect([File.stat(path).mode & 0o777, JSON.parse(File.read(path))['value']]).to eq([0o600, 'token-1'])
    expect(described_class.new(organization).token.value).to eq('token-1')
  end

  it 'refuses CIAM without a client id' do
    expect { session.authorize_url }.to raise_error(Miele::Sdk::ConfigurationError, /ciam_client_id/)
  end

  it 'restores a saved token' do
    token = Miele::Sdk::Cloud::Token.new(value: 'saved', refresh: 'saved', scheme: 'appToken', created_at: now,
                                         expires_at: now + 3600)
    Miele::Sdk.configure { it.cloud_token = token.to_json }
    expect([session.authorization, posts('/V3/Login?org=FR')]).to eq(['appToken saved', []])
  end
end
