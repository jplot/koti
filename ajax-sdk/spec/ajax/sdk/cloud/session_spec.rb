# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Session do
  subject(:session) { described_class.new(client, settings) }

  let(:client) { instance_double(Ajax::Sdk::Cloud::Client) }
  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, email: 'koti@example.com', password_sha256: 'abc123',
                                                        password: nil, totp_secret: 'JBSWY3DPEHPK3PXP',
                                                        session_token: nil, user_id: nil, client_device_id: 'dev',
                                                        client_device_model: 'koti', client_version: '3.59')
  end

  def response(service, hash)
    Ajax::Sdk::Cloud::Messages.type("systems.ajax.api.ecosystem.v3.mobilegwsvc.service.#{service}Response").from(hash)
  end

  def password(hash) = response('login_by_password.LoginByPassword', hash)

  def totp(hash) = response('login_by_totp.LoginByTotp', hash)

  def success(answer = method(:password))
    answer.call({ success: { session_token: "\xAB\xCD".b, lite_account: { user_hex_id: 'user-1' } } })
  end

  def two_factor = password({ failure: { two_fa_required: { request_id: 'req-1' } } })

  def invalid_totp = totp({ failure: { invalid_totp: {} } })

  def totp_success = success(method(:totp))

  it 'logs in with the password hash and keeps the session', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(success)

    session.ensure_login

    expect(client).to have_received(:authenticate)
      .with(anything, have_attributes(password_sha256_hash: 'abc123', user_role: :user), anything)
    expect(session.metadata).to include('client-session-token' => 'ABCD', 'a911-user-id' => 'user-1',
                                        'client-user-role' => 'USER', 'client-user-login' => 'koti@example.com')
  end

  it 'completes a two-factor login with the TOTP code', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(two_factor, totp_success)

    session.ensure_login

    expect(client).to have_received(:authenticate).twice
    expect(session.metadata).to include('client-session-token' => 'ABCD')
  end

  it 'raises invalid_totp after one code, as the app sends one per try', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(two_factor, invalid_totp, totp_success)

    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError) do |error|
      expect(error.reason).to eq(:invalid_totp)
    end
    expect(client).to have_received(:authenticate).twice
  end

  def login_paths
    paths = []
    allow(client).to receive(:authenticate) { |path, request, _metadata| (paths << [path, request]) && yield }
    paths
  end

  it 'answers the same two-factor request at the next call, as the app does', :aggregate_failures do
    answers = [two_factor, invalid_totp, totp_success]
    sent = login_paths { answers.shift }
    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError)
    session.ensure_login

    expect(sent.map { it.first[/login_by_\w+/] }).to eq(%w[login_by_password login_by_totp login_by_totp])
    expect(sent.drop(1).map { it.last.request_id }).to eq(%w[req-1 req-1])
  end

  it 'signs in from the password again once the two-factor request is dropped', :aggregate_failures do
    answers = [two_factor, invalid_totp, two_factor, totp_success]
    sent = login_paths { answers.shift }
    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError)
    session.restart_login
    session.ensure_login

    expect(sent.map { it.first[/login_by_\w+/] })
      .to eq(%w[login_by_password login_by_totp login_by_password login_by_totp])
  end

  it 'raises rather than answer a two-factor request with no id, as the app does', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(password({ failure: { two_fa_required: { request_id: '' } } }))

    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError) do |error|
      expect(error.reason).to eq(:two_fa_required)
    end
    expect(client).to have_received(:authenticate).once
  end

  it 'names a refusal the gateway gives no reason for :unknown, as the app does', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(password({ failure: {} }))

    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError) do |error|
      expect(error.reason).to eq(:unknown)
    end
  end

  def login_outcome
    session.ensure_login
  rescue Ajax::Sdk::Cloud::AuthenticationError => e
    e
  end

  def queued?(threads) = threads.size == 5 && (threads - [Thread.current]).all? { it.status == 'sleep' }

  def refuse_totp_once_all_are_queued(threads)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    allow(client).to receive(:authenticate) do |path|
      Thread.pass while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline && !queued?(threads)
      deadline = 0
      path.include?('login_by_password') ? two_factor : invalid_totp
    end
  end

  it 'raises a refusal to the callers that waited on it, sending nothing more', :aggregate_failures do
    threads = []
    refuse_totp_once_all_are_queued(threads)
    5.times { threads << Thread.new { login_outcome } }

    expect(threads.map { it.value.reason }).to eq([:invalid_totp] * 5)
    expect(client).to have_received(:authenticate).twice
  end

  it 'raises AuthenticationError naming the reason and attempts left', :aggregate_failures do
    refused = password({ failure: { invalid_credentials: {}, attempts_left: 2 } })
    allow(client).to receive(:authenticate).and_return(refused)

    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError, /2 attempts/) do |error|
      expect(error.reason).to eq(:invalid_credentials)
    end
  end

  it 'raises ConfigurationError rather than send a login with no password' do
    allow(settings).to receive_messages(password_sha256: nil, password: nil)

    expect { session.ensure_login }.to raise_error(Ajax::Sdk::ConfigurationError)
  end

  it 'raises when two-factor is required but no secret is configured', :aggregate_failures do
    allow(settings).to receive(:totp_secret).and_return(nil)
    allow(client).to receive(:authenticate).and_return(two_factor)

    expect { session.ensure_login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError) do |error|
      expect(error.reason).to eq(:two_fa_required)
    end
  end

  it 'logs in once when several threads reach ensure_login together' do
    calls = 0
    allow(client).to receive(:authenticate) { sleep(0.01) && (calls += 1) && success }

    Array.new(6) { Thread.new { session.ensure_login } }.each(&:join)

    expect(calls).to eq(1)
  end

  def renewed_tokens
    tokens = Queue.new
    %W[\x01 \x02 \x03 \x04 \x05].each { tokens << it.b }
    allow(client).to receive(:authenticate) do
      sleep(0.01)
      password({ success: { session_token: tokens.pop, lite_account: { user_hex_id: 'user-1' } } })
    end
  end

  it 'signs in again once it forgets a refused session' do
    renewed_tokens
    session.ensure_login
    session.forget(session.metadata['client-session-token'])
    session.ensure_login

    expect(client).to have_received(:authenticate).twice
  end

  it 'returns the call metadata once logged in' do
    allow(client).to receive(:authenticate).and_return(success)

    expect(session.ensure_login).to include('client-session-token' => 'ABCD', 'a911-user-id' => 'user-1')
  end

  it 'signs in once when several threads find the same session refused' do
    renewed_tokens
    expired = session.ensure_login['client-session-token']

    Array.new(4) { Thread.new { session.forget(expired) || session.ensure_login } }.each(&:join)

    expect(client).to have_received(:authenticate).twice
  end

  it 'keeps a session another thread has renewed since the refusal' do
    renewed_tokens
    session.ensure_login
    expired = session.metadata['client-session-token']
    session.forget(expired)
    session.ensure_login
    session.forget(expired)
    session.ensure_login

    expect(client).to have_received(:authenticate).twice
  end

  it 'never prints the token or secrets in inspect' do
    allow(client).to receive(:authenticate).and_return(success)
    session.ensure_login

    expect(session.inspect).to eq('#<Ajax::Sdk::Cloud::Session logged_in=true>')
  end

  it 'sends the code of the current window' do
    requests = []
    answers = [two_factor, totp_success]
    allow(client).to receive(:authenticate) { |_path, request, _metadata| (requests << request) && answers.shift }
    allow(Time).to receive(:now).and_return(Time.at(1_700_000_010))
    session.ensure_login

    expect(requests.last.to_h[:totp]).to eq(ROTP::TOTP.new('JBSWY3DPEHPK3PXP').at(Time.at(1_700_000_010)))
  end
end
