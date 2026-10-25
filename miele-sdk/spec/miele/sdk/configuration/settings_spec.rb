# frozen_string_literal: true

RSpec.describe Miele::Sdk::Configuration::Settings do
  it 'has defaults' do
    expect(Miele::Sdk.config).to have_attributes(port: 80, open_timeout: 5, read_timeout: 10, listener_port: 18_082)
  end

  it 'yields the settings to configure' do
    Miele::Sdk.configure { |config| config.group_id = '0123456789ABCDEF' }
    expect(Miele::Sdk.config.group_id).to eq('0123456789ABCDEF')
  end
end
