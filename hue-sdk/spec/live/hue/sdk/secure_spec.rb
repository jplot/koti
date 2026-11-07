# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure, :live do
  before do
    missing = %w[HUE_ACCOUNT_CLIENT_ID HUE_ACCOUNT_TOKEN_FILE].reject { ENV.key?(it) }
    skip "set #{missing.join(', ')}" unless missing.empty?
    described_class.configure do |config|
      config.client_id = ENV.fetch('HUE_ACCOUNT_CLIENT_ID')
      config.token_file = ENV.fetch('HUE_ACCOUNT_TOKEN_FILE')
    end
    allow(Hue::Sdk::Secure::Http).to receive(:request).and_wrap_original do |original, verb, url, **options|
      raise "live specs are read-only: #{verb.upcase} refused" unless verb == :get || url.end_with?('/oauth/token')

      original.call(verb, url, **options)
    end
  end

  it 'lists the homes of the account' do
    expect(described_class.homes).to include(an_object_having_attributes(id: be_a(String), permissions: be_an(Array)))
  end

  it 'reads the arm state of the first home, which may have none' do
    path = "security/arm-manager/v1/home/#{described_class.homes.first.id}/arm/state"
    status = begin
      described_class.client.get(path).status
    rescue Hue::Sdk::NotFoundError => e
      e.status
    end
    expect(status).to eq(200).or eq(404)
  end

  it 'reads a page of the timeline of the first home' do
    expect(described_class.homes.first.events.page(limit: 5).events).to all(be_a(Hue::Sdk::Secure::MessageEvent))
  end

  it 'reads the arming, the schedules and the geofence clients of the first home, which may have none' do
    home = described_class.homes.first
    read = [-> { home.arm.read }, -> { home.schedules.list }, -> { home.geofence.list }].map do |reading|
      reading.call
    rescue Hue::Sdk::NotFoundError
      :none
    end
    expect(read).to match([be_a(Hue::Sdk::Secure::Schema::ArmDisarmResponse).or(eq(:none)),
                           be_an(Array).or(eq(:none)), be_an(Array).or(eq(:none))])
  end

  it 'lists the cameras of the first home, which may have none' do
    cameras = begin
      described_class.homes.first.cameras.list
    rescue Hue::Sdk::NotFoundError
      []
    end
    expect(cameras).to all(be_a(Hue::Sdk::Secure::Camera))
  end

  it 'follows the first home for a few seconds, without publishing' do
    home = described_class.homes.first
    follower = Thread.new { home.follow { nil } }
    follower.report_on_exception = false
    expect(follower.join(5)).to be_nil
  ensure
    follower&.kill
  end

  it 'reads the automatic responses a doorbell may play' do
    expect(described_class.auto_responses.categories).to all(be_a(Hue::Sdk::Secure::Schema::FetchedAutoResponseCategory))
  end
end
