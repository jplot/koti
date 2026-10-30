# frozen_string_literal: true

RSpec.describe Miele::Sdk::Cloud::Locales do
  let(:cloud) { FakeCloud.start }

  after { cloud.stop }

  it 'finds the rest host and the login system of a country', :aggregate_failures do
    Miele::Sdk.configure { it.locales_host = cloud.url }
    expect(described_class.organization('FR')).to have_attributes(iso: 'FR', rest: cloud.url, ciam: false)
    expect(cloud.requests.map(&:path)).to eq(['/V3/Locales/Countries', '/V3/Locales?org=FR'])
  end

  it 'falls back to the copy of the app when the locales do not answer' do
    Miele::Sdk.configure { it.locales_host = "http://127.0.0.1:#{cloud.port}" }
    cloud.stop
    expect(described_class.organization('FR'))
      .to have_attributes(iso: 'FR', rest: 'https://rest-eu.domestic.miele-iot.com', ciam: false)
  end

  it 'refuses a country the app does not know' do
    Miele::Sdk.configure { it.locales_host = cloud.url }
    expect { described_class.organization('XX') }.to raise_error(Miele::Sdk::ConfigurationError, /XX/)
  end
end
