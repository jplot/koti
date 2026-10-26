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

  def success(token: "\xAB\xCD".b, user: 'user-1')
    { success: { session_token: token, lite_account: { user_hex_id: user } } }
  end

  it 'logs in with the password hash and keeps the session', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(success)

    session.login

    expect(session.metadata).to include('client-session-token' => 'ABCD', 'a911-user-id' => 'user-1',
                                        'client-user-role' => 'USER', 'client-user-login' => 'koti@example.com')
  end

  it 'completes a two-factor login with the TOTP code', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(
      { failure: { two_fa_required: { request_id: 'req-1' } } }, success
    )

    session.login

    expect(client).to have_received(:authenticate).twice
    expect(session.metadata).to include('client-session-token' => 'ABCD')
  end

  it 'retries once with the next window on invalid_totp' do
    allow(client).to receive(:authenticate).and_return(
      { failure: { two_fa_required: { request_id: 'req-1' } } }, { failure: { invalid_totp: {} } }, success
    )

    session.login

    expect(client).to have_received(:authenticate).exactly(3).times
  end

  it 'raises AuthenticationError naming the reason and attempts left', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return({ failure: { invalid_credentials: {}, attempts_left: 2 } })

    expect { session.login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError, /2 attempts/) do |error|
      expect(error.reason).to eq(:invalid_credentials)
    end
  end

  it 'gives up after a second invalid_totp', :aggregate_failures do
    allow(client).to receive(:authenticate).and_return(
      { failure: { two_fa_required: { request_id: 'r' } } }, { failure: { invalid_totp: {} } },
      { failure: { invalid_totp: {} } }
    )

    expect { session.login }.to raise_error(Ajax::Sdk::Cloud::AuthenticationError) do |error|
      expect(error.reason).to eq(:invalid_totp)
    end
  end
end
