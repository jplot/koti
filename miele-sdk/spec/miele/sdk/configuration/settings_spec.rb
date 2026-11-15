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

  it 'caps the connection, the answer and the write of a request by the time the app gives it', :aggregate_failures do
    Miele::Sdk.config.open_timeout = 30
    expect(Miele::Sdk.config.timeouts(8)).to eq(open_timeout: 8, read_timeout: 8, write_timeout: 8)
    expect(Miele::Sdk.config.timeouts).to eq(open_timeout: 30, read_timeout: 10)
  end
end
