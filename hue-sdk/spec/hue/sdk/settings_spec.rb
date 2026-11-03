# frozen_string_literal: true

RSpec.describe Hue::Sdk::Settings do
  let(:key) { 'test-key' }
  let(:config) do
    { name: 'Hue Bridge', bridgeid: 'ECB5FAFFFE000001', modelid: 'BSB003', swversion: '1970000000',
      apiversion: '1.70.0', timezone: 'Europe/Paris', UTC: '2026-11-03T10:00:00', portalservices: true,
      analyticsconsent: false, dhcp: true, ipaddress: '192.0.2.10',
      whitelist: { 'other-client-key' => { name: 'other' } } }
  end
  let(:routes) do
    { "GET /api/#{key}/config" => config,
      "PUT /api/#{key}/config" => [200, [{ success: { '/config/timezone' => 'Europe/London' } }]],
      "GET /api/#{key}/capabilities" => { timezones: { values: %w[Europe/London Europe/Paris] } } }
  end
  let(:bridge) { FakeBridge.serving(routes) }

  before { connect_to(bridge) }

  after { bridge.stop }

  def written = bridge.requests.select { it.verb == 'PUT' }.map { JSON.parse(it.body) }

  it 'reads the settings' do
    expect(Hue::Sdk.settings).to have_attributes(
      name: 'Hue Bridge', bridge_id: 'ECB5FAFFFE000001', model_id: 'BSB003', software_version: '1970000000',
      api_version: '1.70.0', time_zone: 'Europe/Paris', utc: '2026-11-03T10:00:00', remote_access: true,
      analytics_consent: false
    )
  end

  it 'never exposes the keys of other clients nor the network', :aggregate_failures do
    text = Hue::Sdk.settings.inspect
    expect(text).not_to include('other-client-key')
    expect(text).not_to include('192.0.2.10')
  end

  it 'writes the time zone as the app does' do
    Hue::Sdk.settings.update(time_zone: 'Europe/London')
    expect(written).to eq([{ 'timezone' => 'Europe/London' }])
  end

  it 'writes the clock as the app does' do
    Hue::Sdk.settings.update(utc: '2026-11-03T11:00:00')
    expect(written).to eq([{ 'UTC' => '2026-11-03T11:00:00' }])
  end

  it 'blocks plain HTTP as the app does, and allows it again', :aggregate_failures do
    settings = Hue::Sdk.settings
    settings.update(http_blocked: true)
    settings.update(http_blocked: false)
    expect(written).to eq([{ 'blockhttp' => true }, { 'blockhttp' => false }])
  end

  it 'writes each setting in a request of its own, and reads them again', :aggregate_failures do
    updated = Hue::Sdk.settings.update(time_zone: 'Europe/London', http_blocked: true)
    expect(written).to eq([{ 'timezone' => 'Europe/London' }, { 'blockhttp' => true }])
    expect(updated).to be_a(described_class)
  end

  it 'lists the time zones' do
    expect(described_class.time_zones).to eq(%w[Europe/London Europe/Paris])
  end

  context 'when the bridge refuses with a 200' do
    let(:routes) do
      error = { type: 7, address: '/config/timezone', description: 'invalid value' }
      { "GET /api/#{key}/config" => config, "PUT /api/#{key}/config" => [200, [{ error: }]] }
    end

    it 'raises its error, without the key', :aggregate_failures do
      expect { Hue::Sdk.settings.update(time_zone: 'x') }.to raise_error(Hue::Sdk::ResponseError) { |error|
        expect(error.errors).to eq(['invalid value']).and(satisfy { !error.message.include?(key) })
      }
    end
  end

  context 'when the bridge does not know the key' do
    let(:routes) do
      error = { type: 1, address: '/config', description: 'unauthorized user' }
      { "GET /api/#{key}/config" => [200, [{ error: }]] }
    end

    it 'raises AuthenticationError' do
      expect { Hue::Sdk.settings }.to raise_error(Hue::Sdk::AuthenticationError)
    end
  end

  context 'when the bridge answers with an error status' do
    let(:routes) { { "GET /api/#{key}/config" => [503, {}] } }

    it 'raises ResponseError with the status', :aggregate_failures do
      expect { Hue::Sdk.settings }.to raise_error(Hue::Sdk::ResponseError) { expect(it.status).to eq(503) }
    end
  end

  context 'without an application key' do
    before { connect_to(bridge, application_key: nil) }

    it 'raises AuthenticationError' do
      expect { Hue::Sdk.settings }.to raise_error(Hue::Sdk::AuthenticationError)
    end
  end
end
