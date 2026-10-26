# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Configuration::Settings do
  it 'has defaults' do
    expect(Ajax::Sdk.config).to have_attributes(
      grpc_host: 'mobile-gw.prod.ajax.systems', grpc_port: 443, sia_port: 18_083, client_version: '3.59'
    )
  end

  it 'derives a stable client device id from the host name' do
    expect(Ajax::Sdk.config.client_device_id)
      .to eq("#{Digest::SHA256.hexdigest(Socket.gethostname)[0, 16]}_Ajax").and end_with('_Ajax')
  end

  it 'yields the settings to configure' do
    Ajax::Sdk.configure { |config| config.email = 'koti@example.com' }
    expect(Ajax::Sdk.config.email).to eq('koti@example.com')
  end
end
