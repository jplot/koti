# frozen_string_literal: true

require 'digest'
require 'tmpdir'

RSpec.describe Hue::Sdk::Secure::Session do
  subject(:session) { described_class.new(clock: -> { times.last }) }

  let(:now) { Time.at(Time.now.to_i) }
  let(:times) { [now] }
  let(:renewals) { [] }
  let(:cloud) do
    FakeCloud.start do |request|
      next unless request.path == '/oauth/token'

      if request.form['grant_type'] == 'refresh_token'
        renewals.shift || FakeCloud.json(access_token: 'renewed', refresh_token: 'refresh-2', expires_in: 86_400)
      else
        FakeCloud.json(access_token: 'jwt-1', refresh_token: 'refresh-1', expires_in: 100)
      end
    end
  end

  before do
    Hue::Sdk::Secure.configure do |config|
      config.client_id = 'test-client'
      config.login_url = cloud.url
      config.token_file = File.join(Dir.mktmpdir, 'token.json')
    end
  end

  after { cloud.stop }

  def token_posts(grant) = cloud.requests.select { it.path == '/oauth/token' && it.form['grant_type'] == grant }

  def saved = JSON.parse(File.read(Hue::Sdk::Secure.config.token_file))

  def logged_in
    session.authorize_url
    session.exchange('the-code')
  end

  def logging_in?(request) = request.form['grant_type'] == 'authorization_code'

  it 'builds the authorize address with PKCE', :aggregate_failures do
    address = session.authorize_url
    challenge = Digest::SHA256.base64digest(session.verifier).tr('+/', '-_').delete('=')
    expect(address).to start_with("#{cloud.url}/authorize?")
    expect(URI.decode_www_form(URI(address).query).to_h).to match(
      'client_id' => 'test-client', 'redirect_uri' => 'hue-auth0://auth.meethue.com/com.signify.hue/callback',
      'response_type' => 'code', 'scope' => 'openid profile offline_access', 'audience' => 'https://account.meethue.com',
      'state' => /\A[\w-]{20,}\z/, 'code_challenge' => challenge, 'code_challenge_method' => 'S256'
    )
  end

  it 'exchanges the code with the verifier', :aggregate_failures do
    session.authorize_url
    token = session.exchange('the-code')
    expect(token_posts('authorization_code').first.form).to eq(
      'grant_type' => 'authorization_code', 'client_id' => 'test-client', 'code' => 'the-code',
      'code_verifier' => session.verifier, 'redirect_uri' => 'hue-auth0://auth.meethue.com/com.signify.hue/callback'
    )
    expect([token.value, token.refresh, token.expires_at]).to eq(['jwt-1', 'refresh-1', now + 100])
  end

  it 'exchanges a code with a verifier saved elsewhere' do
    session.exchange('the-code', verifier: 'saved-verifier')
    expect(token_posts('authorization_code').first.form['code_verifier']).to eq('saved-verifier')
  end

  it 'writes the token file in mode 0600' do
    logged_in
    expect(File.stat(Hue::Sdk::Secure.config.token_file).mode & 0o777).to eq(0o600)
  end

  it 'writes the token file in mode 0600 over a file others may read' do
    session
    File.write(Hue::Sdk::Secure.config.token_file, '{}', perm: 0o644)
    logged_in
    expect(File.stat(Hue::Sdk::Secure.config.token_file).mode & 0o777).to eq(0o600)
  end

  it 'keeps the token setting current, for the caller to save the rotated refresh token' do
    due = Hue::Sdk::Secure::Token.new(value: 'jwt-0', refresh: 'refresh-0', created_at: now - 86_400, expires_at: now)
    Hue::Sdk::Secure.configure { it.token = due.to_json }
    session.current
    expect(JSON.parse(Hue::Sdk::Secure.config.token).values_at('value', 'refresh')).to eq(%w[renewed refresh-2])
  end

  it 'starts from the token given in the settings' do
    token = Hue::Sdk::Secure::Token.new(value: 'given', refresh: 'r', created_at: now, expires_at: now + 3600)
    Hue::Sdk::Secure.configure { it.token = token.to_json }
    expect(session.current.value).to eq('given')
  end

  it 'raises without client_id' do
    Hue::Sdk::Secure.configure { it.client_id = nil }
    expect { session.authorize_url }.to raise_error(Hue::Sdk::AuthenticationError, /client_id/)
  end

  it 'raises before a login' do
    expect { session.current }.to raise_error(Hue::Sdk::AuthenticationError, /authorize_url/)
  end

  it 'renews a token 30 s before it expires', :aggregate_failures do
    logged_in
    times << (now + 69)
    expect(session.current.value).to eq('jwt-1')
    times << (now + 71)
    expect(session.current.value).to eq('renewed')
  end

  context 'when the token is due' do
    before do
      logged_in
      times << (now + 90)
    end

    it 'sends audience when renewing' do
      session.current
      expect(token_posts('refresh_token').first.form).to eq(
        'grant_type' => 'refresh_token', 'client_id' => 'test-client', 'refresh_token' => 'refresh-1',
        'audience' => 'https://account.meethue.com'
      )
    end

    it 'keeps the refresh token when the answer has none' do
      renewals.push(FakeCloud.json(access_token: 'renewed', expires_in: 86_400))
      expect(session.current.refresh).to eq('refresh-1')
    end

    it 'saves a rotated refresh token' do
      session.current
      expect(saved.values_at('value', 'refresh')).to eq(%w[renewed refresh-2])
    end

    it 'leaves the saved token when the renewal is refused', :aggregate_failures do
      renewals.push(FakeCloud.json({ error: 'invalid_grant', error_description: 'Unknown or invalid refresh token.' },
                                   403))
      expect { session.current }.to raise_error(Hue::Sdk::AuthenticationError, /invalid refresh token/)
      expect([saved['value'], session.token.value]).to eq(%w[jwt-1 jwt-1])
    end

    it 'sends the renewal again on a later call after a failure', :aggregate_failures do
      renewals.push([503, {}, ''])
      expect { session.current }.to raise_error(Hue::Sdk::ResponseError)
      expect(session.current.value).to eq('renewed')
    end

    it 'renews once across threads' do
      Array.new(8) { Thread.new { session.current } }.each(&:join)
      expect(token_posts('refresh_token').size).to eq(1)
    end
  end

  context 'when a thread is killed while renewing' do
    let(:gate) { Thread::SizedQueue.new(1).tap { it << :taken } }
    let(:cloud) do
      FakeCloud.start do |request|
        next unless request.path == '/oauth/token'
        next FakeCloud.json(access_token: 'jwt-1', refresh_token: 'refresh-1', expires_in: 100) if logging_in?(request)

        gate << :renewing
        FakeCloud.json(access_token: 'renewed', refresh_token: 'refresh-2', expires_in: 86_400)
      end
    end

    it 'does not leave an empty file when a thread is killed while renewing' do
      logged_in
      times << (now + 90)
      renewing = Thread.new { session.current }
      Timeout.timeout(5) { Thread.pass until gate.num_waiting == 1 }
      renewing.kill
      gate.pop
      renewing.join
      expect(saved['value']).to eq('renewed')
    end
  end

  context 'when threads wait on a renewal Auth0 refuses' do
    let(:gate) { Thread::SizedQueue.new(1).tap { it << :taken } }
    let(:cloud) do
      first = true
      FakeCloud.start do |request|
        next unless request.path == '/oauth/token'
        next FakeCloud.json(access_token: 'jwt-1', refresh_token: 'refresh-1', expires_in: 100) if logging_in?(request)

        gate << :renewing if first
        first = false
        FakeCloud.json({ error: 'invalid_grant' }, 403)
      end
    end

    def outcome
      yield
    rescue Hue::Sdk::Error => e
      e
    end

    it 'sends the renewal once and raises its refusal in each thread', :aggregate_failures do
      logged_in
      times << (now + 90)
      threads = Array.new(6) { Thread.new { outcome { session.current } } }
      Timeout.timeout(5) { Thread.pass until gate.num_waiting == 1 && threads.all? { it.status == 'sleep' } }
      gate.pop
      expect(threads.map { it.value.class }.uniq).to eq([Hue::Sdk::AuthenticationError])
      expect(token_posts('refresh_token').size).to eq(1)
    end
  end
end
