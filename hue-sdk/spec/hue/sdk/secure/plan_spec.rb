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

  it 'reads the end of an experience period as leniently as the app' do
    expect(status('br-1', 'rid' => 'br-1', 'rtype' => 'bridge', 'xp_end_date' => '2999-01-01 00:00:00Z'))
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

  it 'gives unknown to a device the plans do not list, or when the plans are not read', :aggregate_failures do
    expect(status('cam-2', 'rid' => 'cam-1', 'rtype' => 'camera', 'subscription_ids' => ['sub-1'])).to eq(:unknown)
    expect(described_class.status(nil, 'cam-1')).to eq(:unknown)
  end

  describe "what the app's screens compute" do
    let(:statuses) do
      { subscribed: { 'subscription_ids' => ['sub-1'] },
        experience_period: { 'xp_end_date' => '2999-01-01T00:00:00Z' },
        free_tier: { 'xp_end_date' => '2000-01-01T00:00:00Z' },
        experience_period_not_enabled: { 'xp_enabled' => false },
        unknown: nil }
    end

    def details(status)
      entry = statuses.fetch(status)&.then do |fields|
        [{ 'rid' => 'x-1', 'rtype' => 'camera', 'subscription_ids' => [], 'xp_enabled' => true, **fields }]
      end
      Hue::Sdk::Secure::Schema::AccountSubscriptionDetailsResponse.from('subscriptions' => [], 'devices' => entry || [])
    end

    it 'lets a motion area be picked for arming unless its bridge is free tier or has not started its trial' do
      selectable = statuses.keys.to_h { [it, described_class.motion_area_selectable?(details(it), 'X-1')] }
      expect(selectable).to eq(subscribed: true, experience_period: true, free_tier: false,
                               experience_period_not_enabled: false, unknown: true)
    end

    it 'lets no motion area be picked while the plans are not read' do
      expect(described_class.motion_area_selectable?(nil, 'x-1')).to be(false)
    end

    it "tells what the app does with a camera setting the plan gates, by the camera's status", :aggregate_failures do
      actions = statuses.keys.to_h { [it, described_class.camera_action(details(it), 'x-1')] }
      expect(actions).to eq(subscribed: :run, experience_period: :inform_then_run, free_tier: :suggest_plan,
                            experience_period_not_enabled: :nothing, unknown: :refetch)
      expect(described_class.camera_action(nil, 'x-1')).to eq(:refetch)
    end
  end

  describe '.gated?' do
    let(:schema) { Hue::Sdk::Secure::Schema }

    def service(**fields) = schema::CameraCameraServiceUpdate.new(video_quality: 'high', **fields)

    it 'gates turning clip recording on, unless the free clips are on, and never turning it off', :aggregate_failures do
      expect(described_class.gated?(service(clips_recording: true), free_clips: false)).to be(true)
      expect(described_class.gated?(service(clips_recording: true), free_clips: true)).to be(false)
      expect(described_class.gated?(service(clips_recording: false), free_clips: false)).to be(false)
    end

    it 'gates the activity, package and lighting zones, and sound detection, whatever the value', :aggregate_failures do
      %i[activity_zones package_detection_zones lighting_zones].each do |zones|
        expect(described_class.gated?(service(zones => []), free_clips: true)).to be(true)
      end
      sound = schema::CameraMicrophoneUpdate.new(smoke_alarm_detection: { enabled: false })
      expect(described_class.gated?(sound, free_clips: true)).to be(true)
    end

    it 'leaves the other settings, also given as a plain hash', :aggregate_failures do
      expect(described_class.gated?(service(hdr: true, face_blur: true), free_clips: false)).to be(false)
      expect(described_class.gated?(schema::CameraMicrophoneUpdate.new(enabled: true), free_clips: false)).to be(false)
      expect(described_class.gated?({ 'video_quality' => 'high', 'clips_recording' => true }, free_clips: false))
        .to be(true)
    end
  end

  describe '.covers?' do
    let(:home) { Hue::Sdk::Secure::Home.new(id: 'home-1', bridges: ['br-1'], devices: []) }

    def covers?(home = self.home, plans: [], devices: [], motion_areas: true)
      details = Hue::Sdk::Secure::Schema::AccountSubscriptionDetailsResponse.from(
        'subscriptions' => plans, 'devices' => devices.map { { 'subscription_ids' => [], 'xp_enabled' => true, **it } }
      )
      described_class.covers?(details, home, motion_areas:)
    end

    def plan(product: 'hue.security.plus.monthly', state: 'cancelled', home: 'home-1')
      { 'rid' => 'sub-1', 'user' => { 'rid' => 'user-1' }, 'subscription_product' => { 'rid' => product },
        'homes' => [{ 'rid' => home }], 'scope' => {}, 'subscription_state' => state, 'provider' => 'web',
        'start_date' => '2026-01-01T00:00:00Z' }
    end

    def trial(rid) = { 'rid' => rid, 'rtype' => 'camera', 'xp_end_date' => '2999-01-01T00:00:00Z' }

    it 'counts a paid plan of the home in any state the app knows, and nothing else', :aggregate_failures do
      %w[active grace_period future cancelled].each { expect(covers?(plans: [plan(state: it)])).to be(true) }
      expect(covers?(plans: [plan(product: 'hue.security.freetier')])).to be(false)
      expect(covers?(plans: [plan(state: 'paused')])).to be(false)
      expect(covers?(plans: [plan(home: 'HOME-1')])).to be(false)
    end

    it 'counts a camera of the home in its trial, by product type', :aggregate_failures do
      camera = Hue::Sdk::Secure::Home::Device.new(type: 'CMB001', id: 'cam-1')
      other = Hue::Sdk::Secure::Home::Device.new(type: 'BSB002', id: 'cam-1')
      expect(covers?(home.with(devices: [camera]), devices: [trial('CAM-1')])).to be(true)
      expect(covers?(home.with(devices: [other]), devices: [trial('cam-1')])).to be(false)
      subscribed = { 'rid' => 'cam-1', 'rtype' => 'camera', 'subscription_ids' => ['sub-1'] }
      expect(covers?(home.with(devices: [camera]), devices: [subscribed])).to be(false)
      ended = trial('cam-1').merge('xp_end_date' => '2000-01-01T00:00:00Z')
      expect(covers?(home.with(devices: [camera]), devices: [ended, trial('cam-1')])).to be(true)
    end

    it 'counts a bridge of the home in its trial, its id upper-cased as the app compares it', :aggregate_failures do
      expect(covers?(devices: [trial('BR-1').merge('rtype' => 'bridge')])).to be(true)
      expect(covers?(devices: [trial('br-1').merge('rtype' => 'bridge')])).to be(false)
      expect(covers?(devices: [trial('BR-1').merge('rtype' => 'speaker')])).to be(false)
    end

    it "counts a bridge's trial only when the home has a motion area, and nothing unread", :aggregate_failures do
      expect(covers?(devices: [trial('BR-1').merge('rtype' => 'bridge')], motion_areas: false)).to be(false)
      expect(described_class.covers?(nil, home, motion_areas: true)).to be(false)
    end
  end
end
