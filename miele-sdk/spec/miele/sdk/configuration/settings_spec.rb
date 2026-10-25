# frozen_string_literal: true

RSpec.describe Miele::Sdk::Configuration::Settings do
  it 'has defaults' do
    expect(Miele::Sdk.config).to have_attributes(port: 80, open_timeout: 5, read_timeout: 10, listener_port: 18_082)
  end

  it 'derives a listener fabrication number from the host name' do
    expect(Miele::Sdk.config.listener_fab)
      .to eq(format('000999%06d', Zlib.crc32(Socket.gethostname) % 1_000_000)).and match(/\A000999\d{6}\z/)
  end

  it 'yields the settings to configure' do
    Miele::Sdk.configure { |config| config.group_id = '0123456789ABCDEF' }
    expect(Miele::Sdk.config.group_id).to eq('0123456789ABCDEF')
  end
end
