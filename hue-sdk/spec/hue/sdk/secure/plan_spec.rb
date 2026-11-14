# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Plan do
  def status(rid, *devices)
    details = Hue::Sdk::Secure::Schema::AccountSubscriptionDetailsResponse.from(
      'subscriptions' => [], 'devices' => devices.map { { 'subscription_ids' => [], 'xp_enabled' => true, **it } }
    )
    described_class.status(details, rid)
  end

  it 'gives subscribed to a device a plan covers, whatever its experience period', :aggregate_failures do
    expect(status('cam-1', 'rid' => 'cam-1', 'rtype' => 'camera', 'subscription_ids' => ['sub-1'],
                           'xp_enabled' => false)).to eq(:subscribed)
    expect(status('tv-1', 'rid' => 'tv-1', 'rtype' => 'tv', 'subscription_ids' => ['sub-1'])).to eq(:subscribed)
  end

  it 'reads the experience period of a device no plan covers', :aggregate_failures do
    expect(status('br-1', 'rid' => 'br-1', 'rtype' => 'bridge', 'xp_enabled' => false))
      .to eq(:experience_period_not_enabled)
    expect(status('br-1', 'rid' => 'br-1', 'rtype' => 'bridge')).to eq(:unknown)
    expect(status('br-1', 'rid' => 'br-1', 'rtype' => 'bridge', 'xp_end_date' => '2000-01-01T00:00:00Z'))
      .to eq(:free_tier)
    expect(status('br-1', 'rid' => 'br-1', 'rtype' => 'bridge', 'xp_end_date' => '2999-01-01T00:00:00Z'))
      .to eq(:experience_period)
  end

  it 'matches the id ignoring case, as the app does' do
    expect(status('CAM-1', 'rid' => 'cam-1', 'rtype' => 'camera', 'subscription_ids' => ['sub-1']))
      .to eq(:subscribed)
  end

  it 'skips an unknown device type, and a tv no plan covers', :aggregate_failures do
    expect(status('x-1', { 'rid' => 'x-1', 'rtype' => 'speaker', 'subscription_ids' => ['sub-1'] },
                  { 'rid' => 'x-1', 'rtype' => 'camera', 'xp_enabled' => false }))
      .to eq(:experience_period_not_enabled)
    expect(status('tv-1', 'rid' => 'tv-1', 'rtype' => 'tv', 'xp_enabled' => false)).to eq(:unknown)
  end

  it 'gives unknown to a device the plans do not list' do
    expect(status('cam-2', 'rid' => 'cam-1', 'rtype' => 'camera', 'subscription_ids' => ['sub-1'])).to eq(:unknown)
  end
end
