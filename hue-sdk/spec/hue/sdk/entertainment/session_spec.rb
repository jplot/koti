# frozen_string_literal: true

require 'hue/sdk/entertainment'

RSpec.describe Hue::Sdk::Entertainment::Session do
  let(:id) { '1a8d99cc-967b-44f2-9202-43f976c0fa6b' }
  let(:bridge) do
    done = { data: [], errors: [] }
    area = "/clip/v2/resource/entertainment_configuration/#{id}"
    services = %w[l1 l2 l3].map { { rid: it, rtype: 'light' } }
    FakeBridge.serving(
      "GET #{area}" => { data: [{ id:, light_services: services }], errors: [] },
      'GET /clip/v2/resource/light' => { data: lights, errors: [] },
      "PUT #{area}" => done, **%w[l1 l2 l3].to_h { ["PUT /clip/v2/resource/light/#{it}", done] }
    )
  end
  let(:socket) { instance_double(Hue::Sdk::Entertainment::DtlsSocket, write: 59, close: nil) }
  let(:configuration) { Hue::Sdk.EntertainmentConfiguration(id) }

  before do
    connect_to(bridge)
    Hue::Sdk.config.client_key = '0123456789abcdef0123456789abcdef'
    allow(Hue::Sdk::Entertainment::DtlsSocket).to receive(:open).and_return(socket)
  end

  after { bridge.stop }

  def lights
    [{ id: 'l1', on: { on: true }, dimming: { brightness: 40.0 }, color_temperature: { mirek: 300, mirek_valid: true },
       color: { xy: { x: 0.45, y: 0.41 } } },
     { id: 'l2', on: { on: false }, dimming: { brightness: 10.0 } },
     { id: 'l3', on: { on: true }, dimming: { brightness: 80.0 }, color_temperature: { mirek: nil, mirek_valid: false },
       color: { xy: { x: 0.69, y: 0.31 } } },
     { id: 'l9', on: { on: true } }]
  end

  def restored
    [['l1', { 'on' => { 'on' => true }, 'dimming' => { 'brightness' => 40.0 },
              'color_temperature' => { 'mirek' => 300 } }],
     ['l2', { 'on' => { 'on' => false } }],
     ['l3', { 'on' => { 'on' => true }, 'dimming' => { 'brightness' => 80.0 },
              'color' => { 'xy' => { 'x' => 0.69, 'y' => 0.31 } } }]]
  end

  def red = { 0 => [1.0, 0.0, 0.0] }

  def writes = bridge.requests.select { it.verb == 'PUT' }.map { [it.path.split('/').last, JSON.parse(it.body)] }

  def actions = writes.filter_map { |target, body| body['action'] if target == id }

  it 'starts and stops the configuration around the block', :aggregate_failures do
    configuration.stream { |session| session.write(red) }
    expect(actions).to eq(%w[start stop])
    expect(socket).to have_received(:write)
      .with(Hue::Sdk::Entertainment::Message.encode(configuration_id: id, sequence: 0, channels: red))
    expect(socket).to have_received(:close)
  end

  it 'puts the lights of the area back as they were, after stopping' do
    configuration.stream { nil }
    expect(writes.drop(2)).to eq(restored)
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

  it 'stops the configuration and restores the lights when the block raises', :aggregate_failures do
    expect { configuration.stream { raise 'boom' } }.to raise_error('boom')
    expect(writes.map(&:first)).to eq([id, id, 'l1', 'l2', 'l3'])
  end

  it 'requires the client key', :aggregate_failures do
    Hue::Sdk.config.client_key = nil
    expect { configuration.stream { nil } }.to raise_error(Hue::Sdk::AuthenticationError, /client_key/)
    expect(bridge.requests).to be_empty
  end
end
