# frozen_string_literal: true

RSpec.describe Hue::Sdk::Configuration::Settings do
  it 'has defaults' do
    expect(Hue::Sdk.config).to have_attributes(port: 443, open_timeout: 5, read_timeout: 10, event_read_timeout: 300)
  end

  it 'yields the settings to configure' do
    Hue::Sdk.configure { |config| config.host = '192.0.2.10' }
    expect(Hue::Sdk.config.host).to eq('192.0.2.10')
  end
end
