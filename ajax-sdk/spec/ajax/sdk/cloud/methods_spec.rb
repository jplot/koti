# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Methods do
  subject(:client) { Ajax::Sdk::Cloud::Client.new(settings) }

  let(:settings) do
    instance_double(Ajax::Sdk::Configuration::Settings, grpc_host: 'gw', grpc_port: 443, read_timeout: 30,
                                                        ca_file: nil, read_only: false, session_token: 'tok',
                                                        user_id: 'uid')
  end
  let(:grpc) { instance_double(GRPC::ClientStub, request_response: nil) }
  let(:locator) { Ajax::Sdk::Cloud::Messages::Api::Mobile::V2::Common::Space::SpaceLocator.new(space_id: 'space-1') }

  before do
    allow(GRPC::ClientStub).to receive(:new).and_return(grpc)
    allow(client.session).to receive_messages(ensure_login: {}, metadata: {})
  end

  def answer(path, message = { success: {} })
    klass = Ajax::Sdk::Cloud::Schemas.message(Ajax::Sdk::Cloud::Schemas.rpc(path).response)
    klass.encode(klass.new(message))
  end

  it 'clashes with no method of the client' do
    owners = [Ajax::Sdk::Cloud::Client, Ajax::Sdk::Cloud::Resources]
    taken = Object.instance_methods + Object.private_instance_methods +
            owners.flat_map { it.instance_methods(false) + it.private_instance_methods(false) }

    expect(described_class.instance_methods & taken).to be_empty
  end

  it 'sends the request of a named method' do
    sent = []
    allow(grpc).to receive(:request_response) do |path, request, *|
      sent << [path, request.to_h[:group_id]]
      answer(path)
    end

    client.space_security_arm_group(space_locator: locator, group_id: 'g1')

    expect(sent).to eq([['/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/armGroup', 'g1']])
  end

  it 'rejects an unknown keyword before sending', :aggregate_failures do
    expect { client.space_security_arm_group(bogus: 1) }.to raise_error(ArgumentError, /bogus/)
    expect(grpc).not_to have_received(:request_response)
  end

  it 'rejects a wrong type before sending', :aggregate_failures do
    expect { client.space_security_arm_group(group_id: 1) }.to raise_error(Google::Protobuf::TypeError)
    expect(client.session).not_to have_received(:ensure_login)
    expect(grpc).not_to have_received(:request_response)
  end

  it 'rejects a Hash for a sub-message before sending', :aggregate_failures do
    expect { client.space_security_arm_group(space_locator: { space_id: 'space-1' }) }
      .to raise_error(TypeError, /SpaceLocator/)
    expect(grpc).not_to have_received(:request_response)
  end

  it 'refuses a named command when read-only' do
    allow(settings).to receive(:read_only).and_return(true)

    expect { client.space_security_arm_group(group_id: 'g1') }.to raise_error(Ajax::Sdk::Cloud::ReadOnlyError)
  end

  it 'yields typed values from a named stream' do
    path = '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.stream_light_devices.StreamLightDevicesService/execute'
    allow(grpc).to receive(:server_streamer) { |*, &relay| relay.call(answer(path)) }
    response = Ajax::Sdk::Cloud::Messages.type(Ajax::Sdk::Cloud::Schemas.rpc(path).response)

    expect(client.stream_light_devices(space_id: 'space-1').to_a).to contain_exactly(be_a(response::Success))
  end
end
