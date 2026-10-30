# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Client, '#server_stream' do
  subject(:client) { described_class.new(settings) }

  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'local', grpc_port: 0, read_timeout: 0.2,
                                                        ca_file: nil, read_only: false, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:devices) do
    '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service' \
      '.stream_light_devices.StreamLightDevicesService/execute'
  end
  let(:gateway) { FakeGateway.start(devices, count:, pause:) }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_wrap_original do |original, *, **options|
      original.call("127.0.0.1:#{gateway.port}", :this_channel_is_insecure, **options)
    end
    allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
  end

  after { gateway.stop }

  context 'when the stream outlasts the read timeout' do
    let(:count) { 3 }
    let(:pause) { 0.15 }

    it 'delivers every message' do
      collected = []

      client.server_stream(devices, { space_id: 's1' }) { |message| collected << message }

      expect(collected.size).to eq(3)
    end
  end

  context 'when a message is a failure' do
    let(:gateway) do
      FakeGateway.start(devices, count: 100, pause: 0.05, first: [{ success: {} }, { failure: { bad_request: {} } }])
    end

    it 'raises and closes the call on the server', :aggregate_failures do
      expect { client.server_stream(devices, { space_id: 's1' }) { nil } }
        .to raise_error(Ajax::Sdk::Cloud::ReadError, 'bad_request')
      expect(gateway.closed.pop(timeout: 1)).to eq(devices)
    end
  end

  context 'when the caller leaves early' do
    let(:count) { 100 }
    let(:pause) { 0.05 }

    it 'closes the call on the server' do
      client.server_stream(devices, { space_id: 's1' }).first

      expect(gateway.closed.pop(timeout: 1)).to eq(devices)
    end
  end
end
