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

  describe '.covers?' do
    let(:home) { Hue::Sdk::Secure::Home.new(id: 'home-1', bridges: ['br-1'], devices: []) }

    def covers?(home = self.home, plans: [], devices: [])
      details = Hue::Sdk::Secure::Schema::AccountSubscriptionDetailsResponse.from(
        'subscriptions' => plans, 'devices' => devices.map { { 'subscription_ids' => [], 'xp_enabled' => true, **it } }
      )
      described_class.covers?(details, home)
    end

    def plan(product: 'hue.security.plus.monthly', state: 'cancelled', home: 'home-1')
      { 'rid' => 'sub-1', 'user' => { 'rid' => 'user-1' }, 'subscription_product' => { 'rid' => product },
        'homes' => [{ 'rid' => home }], 'scope' => {}, 'subscription_state' => state, 'provider' => 'web',
        'start_date' => '2026-01-01T00:00:00Z' }
    end

    def trial(rid) = { 'rid' => rid, 'rtype' => 'camera', 'xp_end_date' => '2999-01-01T00:00:00Z' }

    it 'counts a paid plan of the home in any state the app knows, and nothing else', :aggregate_failures do
      expect(covers?(plans: [plan])).to be(true)
      expect(covers?(plans: [plan(product: 'hue.security.freetier')])).to be(false)
      expect(covers?(plans: [plan(state: 'paused')])).to be(false)
      expect(covers?(plans: [plan(home: 'home-2')])).to be(false)
    end

    it 'counts a camera of the home in its trial, by product type', :aggregate_failures do
      camera = Hue::Sdk::Secure::Home::Device.new(type: 'CMB001', id: 'cam-1')
      other = Hue::Sdk::Secure::Home::Device.new(type: 'BSB002', id: 'cam-1')
      expect(covers?(home.with(devices: [camera]), devices: [trial('CAM-1')])).to be(true)
      expect(covers?(home.with(devices: [other]), devices: [trial('cam-1')])).to be(false)
      subscribed = { 'rid' => 'cam-1', 'rtype' => 'camera', 'subscription_ids' => ['sub-1'] }
      expect(covers?(home.with(devices: [camera]), devices: [subscribed])).to be(false)
    end

    it 'counts a bridge of the home in its trial, its id upper-cased as the app compares it', :aggregate_failures do
      expect(covers?(devices: [trial('BR-1').merge('rtype' => 'bridge')])).to be(true)
      expect(covers?(devices: [trial('br-1').merge('rtype' => 'bridge')])).to be(false)
    end
  end
end
