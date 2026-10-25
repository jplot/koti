# frozen_string_literal: true

require 'hue/sdk/entertainment'

RSpec.describe Hue::Sdk::Entertainment::Session do
  let(:id) { '1a8d99cc-967b-44f2-9202-43f976c0fa6b' }
  let(:bridge) do
    FakeBridge.serving("PUT /clip/v2/resource/entertainment_configuration/#{id}" =>
                         { data: [{ rid: id, rtype: 'entertainment_configuration' }], errors: [] })
  end
  let(:socket) { instance_double(Hue::Sdk::Entertainment::DtlsSocket, write: 59, close: nil) }
  let(:configuration) { Hue::Sdk.EntertainmentConfiguration(id) }
  let(:red) { { 0 => [1.0, 0.0, 0.0] } }

  before do
    connect_to(bridge)
    Hue::Sdk.config.client_key = '0123456789abcdef0123456789abcdef'
    allow(Hue::Sdk::Entertainment::DtlsSocket).to receive(:open).and_return(socket)
  end

  after { bridge.stop }

  def actions = bridge.requests.map { JSON.parse(it.body)['action'] }

  it 'starts and stops the configuration around the block', :aggregate_failures do
    configuration.stream { |session| session.write(red) }
    expect(actions).to eq(%w[start stop])
    expect(socket).to have_received(:write)
      .with(Hue::Sdk::Entertainment::Message.encode(configuration_id: id, sequence: 0, channels: red))
    expect(socket).to have_received(:close)
  end

  it 'opens the DTLS socket with the application key and the client key' do
    configuration.stream { nil }
    expect(Hue::Sdk::Entertainment::DtlsSocket).to have_received(:open)
      .with(host: '127.0.0.1', identity: 'test-key', psk: ['0123456789abcdef0123456789abcdef'].pack('H*'))
  end

  it 'numbers the messages' do
    configuration.stream { |session| 2.times { session.write({ 0 => [0.0, 0.0, 0.0] }, color_space: :xy) } }
    expect(socket).to have_received(:write).with(satisfy { it.getbyte(11) == 1 && it.getbyte(14) == 1 })
  end

  it 'stops the configuration when the block raises', :aggregate_failures do
    expect { configuration.stream { raise 'boom' } }.to raise_error('boom')
    expect(actions).to eq(%w[start stop])
  end

  it 'requires the client key', :aggregate_failures do
    Hue::Sdk.config.client_key = nil
    expect { configuration.stream { nil } }.to raise_error(Hue::Sdk::AuthenticationError, /client_key/)
    expect(bridge.requests).to be_empty
  end
end
