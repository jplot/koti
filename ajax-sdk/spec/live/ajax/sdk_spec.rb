# frozen_string_literal: true

# Live, read-only checks against the real Ajax cloud. They run only with AJAX_LIVE=1 and the account
# in the environment (AJAX_EMAIL, AJAX_PASSWORD_SHA256, AJAX_TOTP_SECRET). The client is read-only, so
# no command ever reaches the hub.
RSpec.describe 'Ajax cloud', :live do # rubocop:disable RSpec/DescribeClass -- integration spec, not a class
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll -- one login shared across read-only checks
    Ajax::Sdk.configure do |config|
      config.email = ENV.fetch('AJAX_EMAIL')
      config.password_sha256 = ENV.fetch('AJAX_PASSWORD_SHA256')
      config.totp_secret = ENV.fetch('AJAX_TOTP_SECRET')
      config.read_only = true
    end
  end

  let(:cloud) { Ajax::Sdk.cloud }
  let(:space) { cloud.spaces.first }

  it 'logs in with two-factor authentication and lists at least one space' do
    expect(cloud.spaces).not_to be_empty
  end

  it 'reads the devices of a space as a snapshot' do
    expect(cloud.devices(space.id)).to all(be_an(Ajax::Sdk::Cloud::Device))
  end

  it 'reads recent notifications of a space' do
    expect(cloud.notifications(space.id, limit: 5)).to all(be_an(Ajax::Sdk::Cloud::Notification))
  end

  it 'refuses to arm because the client is read-only' do
    expect { cloud.arm(space.id) }.to raise_error(Ajax::Sdk::Cloud::ReadOnlyError)
  end
end
