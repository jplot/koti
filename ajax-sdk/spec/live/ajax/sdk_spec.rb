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

  def unless_refused
    yield
  rescue Ajax::Sdk::Cloud::ReadError => e
    raise unless e.reason == :permission_denied

    skip "the koti account's role is refused this read (#{e.reason})"
  end

  it 'logs in with two-factor authentication and lists at least one space' do
    expect(cloud.spaces).not_to be_empty
  end

  it 'reads the devices of a space as a snapshot' do
    expect(cloud.devices(space.id)).to all(be_an(Ajax::Sdk::Cloud::Device).and(have_attributes(space_id: space.id)))
  end

  it 'reads recent notifications of a space' do
    expect(cloud.notifications(space.id, limit: 5)).to all(be_an(Ajax::Sdk::Cloud::Notification))
  end

  it 'refuses to arm because the client is read-only' do
    expect { cloud.arm(space.id) }.to raise_error(Ajax::Sdk::Cloud::ReadOnlyError)
  end

  it 'reads the rooms and the groups of a space', :aggregate_failures do
    expect(unless_refused { cloud.rooms(space.id) }).to all(have_attributes(id: be_a(String), name: be_a(String)))
    expect(unless_refused { cloud.groups(space.id) }).to all(have_attributes(id: be_a(String)))
  end

  it 'reads the scenarios of a space' do
    expect(unless_refused { cloud.scenarios(space.id) }).to all(have_attributes(id: be_a(String)))
  end

  it 'reads the details of the hub and of a device', :aggregate_failures do
    device = cloud.devices(space.id).find(&:hub_id)

    expect(unless_refused { cloud.hub_details(space.id, space.hub_id) }).not_to be_nil
    expect(unless_refused { cloud.device_details(device) }).not_to be_nil
  end

  it 'reads the LifeQuality history of a device' do
    device = cloud.devices(space.id).find(&:life_quality) or skip 'no LifeQuality device in this space'

    history = unless_refused { cloud.life_quality_history(device, from: Time.now - 86_400, to: Time.now) }
    expect(history).to be_a(Ajax::Sdk::Cloud::LifeQualityHistory)
  end
end
