# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Client do
  subject(:client) { described_class.new(settings) }

  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'gw', grpc_port: 443, read_timeout: 30,
                                                        ca_file: nil, read_only: false, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:grpc) { instance_double(GRPC::ClientStub) }
  let(:stream_options) { [] }
  let(:spaces) { '/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination' }
  let(:devices) do
    '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service' \
      '.stream_light_devices.StreamLightDevicesService/execute'
  end

  before do
    allow(GRPC::ClientStub).to receive(:new).and_return(grpc)
    allow(client.session).to receive_messages(ensure_login: {}, metadata: {})
  end

  def answer(path, message = { success: {} })
    klass = Ajax::Sdk::Cloud::Schemas.message(Ajax::Sdk::Cloud::Schemas.rpc(path).response)
    klass.encode(klass.new(message))
  end

  def type(path) = Ajax::Sdk::Cloud::Messages.type(Ajax::Sdk::Cloud::Schemas.rpc(path).response)

  def streaming(*answers)
    allow(grpc).to receive(:server_streamer) do |*, **options, &relay|
      stream_options << options
      answers.each { |answer| answer.is_a?(Exception) ? raise(answer) : relay.call(answer) }
    end
  end

  it 'returns the success of a unary call as a typed value' do
    allow(grpc).to receive(:request_response).and_return(answer(spaces, success: { spaces: [{ id: 's1' }] }))

    expect(client.call(spaces)).to be_a(type(spaces)::Success).and(have_attributes(spaces: [have_attributes(id: 's1')]))
  end

  it 'raises CommandError with the reason and its details', :aggregate_failures do
    arm = '/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm'
    refusal = { failure: { hub_detected_malfunctions: { troubled_devices: {} } } }
    allow(grpc).to receive(:request_response).and_return(answer(arm, refusal))

    expect { client.call(arm, { space_locator: { space_id: 's1' } }) }
      .to raise_error(Ajax::Sdk::Cloud::CommandError) do |error|
      expect(error).to have_attributes(reason: :hub_detected_malfunctions, failure: type(arm)::Failure)
      expect(error.details.troubled_devices).to be_a(Data)
    end
  end

  it 'raises ReadError :refused for an answer without success or failure', :aggregate_failures do
    allow(grpc).to receive(:request_response).and_return(answer(spaces, {}))

    expect { client.call(spaces) }.to raise_error(Ajax::Sdk::Cloud::ReadError) { expect(it.reason).to eq(:refused) }
  end

  it 'raises from a stream whose message is a failure', :aggregate_failures do
    streaming(answer(devices), answer(devices, failure: { bad_request: {} }))
    collected = []

    expect { client.call(devices, { space_id: 's1' }) { collected << it } }
      .to raise_error(Ajax::Sdk::Cloud::ReadError, 'bad_request')
    expect(collected).to contain_exactly(be_a(type(devices)::Success))
  end

  it 'builds a stream request at the call, before returning an Enumerator', :aggregate_failures do
    ping = '/systems.ajax.api.mobile.v2.connectivity.PingPongService/pingPong'

    expect { client.server_stream(devices, { space_id: 1 }) }.to raise_error(Google::Protobuf::TypeError)
    expect { client.bidi(ping, [{ bogus: 1 }]) }.to raise_error(ArgumentError, /bogus/)
  end

  it 'sends a typed request' do
    sent = []
    allow(grpc).to receive(:request_response) { |_path, request, *| (sent << request) && answer(spaces) }
    request = Ajax::Sdk::Cloud::Messages.type(Ajax::Sdk::Cloud::Schemas.rpc(spaces).request).new(limit: 5)

    client.call(spaces, request)

    expect(sent.map { it.to_h[:limit] }).to eq([5])
  end

  it 'yields each message of a server stream' do
    streaming(answer(devices))
    collected = []

    client.call(devices, { space_id: 's1' }) { |message| collected << message }

    expect(collected.size).to eq(1)
  end

  it 'returns an Enumerator from a stream called without a block' do
    streaming(answer(devices))

    expect(client.server_stream(devices, { space_id: 's1' }).first).to be_a(type(devices)::Success)
  end

  it 'raises rather than replay a stream whose session expires after a message', :aggregate_failures do
    streaming(answer(devices), GRPC::Unauthenticated.new('expired'))
    collected = []

    expect { client.server_stream(devices, { space_id: 's1' }) { |message| collected << message } }
      .to raise_error(GRPC::Unauthenticated)
    expect(collected.size).to eq(1)
  end

  it 'raises a stream refused before its first message, opening it once', :aggregate_failures do
    streaming(GRPC::Unauthenticated.new('expired'))

    expect { client.server_stream(devices, { space_id: 's1' }) { nil } }.to raise_error(GRPC::Unauthenticated)
    expect(grpc).to have_received(:server_streamer).once
  end

  it 'gives unary calls a deadline and leaves streams without one', :aggregate_failures do
    unary_options = []
    allow(grpc).to receive(:request_response) { |*, **options| (unary_options << options) && answer(spaces) }
    streaming(answer(devices))

    client.call(spaces)
    client.call(devices, { space_id: 's1' }) { |_message| nil }

    expect(GRPC::ClientStub).to have_received(:new).with('gw:443', anything)
    expect(unary_options.first[:deadline]).to be_within(1).of(Time.now + 30)
    expect(stream_options.first).not_to have_key(:deadline)
  end

  it 'refuses a command sent through the generic call when read-only' do
    allow(settings).to receive(:read_only).and_return(true)
    arm = '/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm'

    expect { client.call(arm, { space_locator: { space_id: 's1' } }) }
      .to raise_error(Ajax::Sdk::Cloud::ReadOnlyError)
  end

  it 'still allows a read through the generic call when read-only' do
    allow(settings).to receive(:read_only).and_return(true)
    allow(grpc).to receive(:request_response).and_return(answer(spaces))

    expect(client.call(spaces)).to be_a(type(spaces)::Success)
  end

  context 'when read-only' do
    before { allow(settings).to receive(:read_only).and_return(true) }

    def gateway(name) = "/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.#{name}Service/execute"

    it 'refuses the server streams that change state, before any call', :aggregate_failures do
      writes = %w[stream_create_access_card.StreamCreateAccessCard stream_radio_test.StreamRadioTest
                  stream_z_wave_device_registration.classic_inclusion.StreamZWaveDeviceClassicInclusionRegistration]
      writes.each do |name|
        expect { client.call(gateway(name), {}) }.to raise_error(Ajax::Sdk::Cloud::ReadOnlyError), name
      end
    end

    it 'lets the raw reads through', :aggregate_failures do
      reads = [gateway('get_device_parts.GetDeviceParts'), gateway('find_single_notification.FindSingleNotification'),
               '/systems.ajax.api.mobile.v2.space.scenario.ScenarioService/findAll']
      reads.each do |path|
        allow(grpc).to receive(:request_response).and_return(answer(path))
        expect { client.call(path) }.not_to raise_error, path
      end
    end
  end

  it 'drops the session the gateway refuses and raises, as the app does', :aggregate_failures do
    allow(grpc).to receive(:request_response).and_raise(GRPC::Unauthenticated, 'nope')
    allow(client.session).to receive_messages(ensure_login: { 'client-session-token' => 'sent' },
                                              metadata: { 'client-session-token' => 'renewed' }, forget: nil)

    expect { client.unary(spaces) }.to raise_error(GRPC::Unauthenticated)
    expect(client.session).to have_received(:forget).with('sent')
    expect(grpc).to have_received(:request_response).once
  end
end
