# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Client do
  subject(:client) { described_class.new(settings) }

  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'gw', grpc_port: 443, read_timeout: 30,
                                                        ca_file: nil, read_only: false, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:grpc) { instance_double(GRPC::ClientStub) }
  let(:spaces) { '/systems.ajax.api.mobile.v2.space.SpaceService/findUserSpacesWithPagination' }
  let(:devices) do
    '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service' \
      '.stream_light_devices.StreamLightDevicesService/execute'
  end

  before do
    allow(client).to receive(:stub).and_return(grpc) # rubocop:disable RSpec/SubjectStub -- inject a gRPC double
    allow(client.session).to receive_messages(ensure_login: nil, login: nil, metadata: {})
  end

  def empty_response(path)
    klass = Ajax::Sdk::Cloud::Schemas.message(Ajax::Sdk::Cloud::Schemas.rpc(path).response)
    klass.encode(klass.new)
  end

  it 'makes a unary call and returns a Hash' do
    allow(grpc).to receive(:request_response).and_return(empty_response(spaces))

    expect(client.call(spaces)).to be_a(Hash)
  end

  it 'yields each message of a server stream' do
    allow(grpc).to receive(:server_streamer).and_yield(empty_response(devices))
    collected = []

    client.call(devices, { space_id: 's1' }) { |message| collected << message }

    expect(collected.size).to eq(1)
  end

  it 'refuses a command sent through the generic call when read-only' do
    allow(settings).to receive(:read_only).and_return(true)
    arm = '/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm'

    expect { client.call(arm, { space_locator: { space_id: 's1' } }) }
      .to raise_error(Ajax::Sdk::Cloud::ReadOnlyError)
  end

  it 'still allows a read through the generic call when read-only' do
    allow(settings).to receive(:read_only).and_return(true)
    allow(grpc).to receive(:request_response).and_return(empty_response(spaces))

    expect(client.call(spaces)).to be_a(Hash)
  end

  it 'logs in again and retries once after an Unauthenticated answer' do
    answers = [-> { raise GRPC::Unauthenticated, 'nope' }, -> { empty_response(spaces) }]
    allow(grpc).to receive(:request_response) { answers.shift.call }

    client.unary(spaces)

    expect(client.session).to have_received(:login).once
  end
end
