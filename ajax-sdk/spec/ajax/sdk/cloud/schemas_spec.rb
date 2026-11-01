# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Schemas do
  describe '.rpc' do
    it 'knows the login method is unary with its request', :aggregate_failures do
      rpc = described_class.rpc(
        '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.login_by_password.LoginByPasswordService/execute'
      )

      expect(rpc.type).to eq(:unary)
      expect(rpc.request).to end_with('login_by_password.LoginByPasswordRequest')
    end

    it 'gives a v3 method the v3 message of the same name as its v2 one' do
      rpc = described_class.rpc(
        '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.get_device_about.GetDeviceAboutService/execute'
      )

      expect(rpc.response)
        .to eq('systems.ajax.api.ecosystem.v3.mobilegwsvc.service.get_device_about.GetDeviceAboutResponse')
    end

    it 'knows that arming a space is unary' do
      rpc = described_class.rpc('/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm')

      expect(rpc.type).to eq(:unary)
    end

    it 'streams the user spaces with messages it can load', :aggregate_failures do
      rpc = described_class.rpc('/systems.ajax.api.mobile.v2.space.SpaceService/streamUserSpaces')

      expect(rpc.type).to eq(:server_stream)
      expect([rpc.request, rpc.response].map { described_class.message(it) }).to all(be_a(Class))
    end

    it 'raises UnknownMethodError for a path it does not know' do
      expect { described_class.rpc('/Nope/nope') }.to raise_error(Ajax::Sdk::Cloud::UnknownMethodError, %r{/Nope/nope})
    end
  end

  describe '.message' do
    it 'loads a message class from the shipped schemas', :aggregate_failures do
      klass = described_class.message('systems.ajax.api.mobile.v2.common.space.LiteSpace')

      expect(klass).to be_a(Class)
      expect(klass.new(id: 'space-1').to_h).to include(id: 'space-1')
    end

    it 'raises UnknownMessageError for a message it does not know' do
      expect { described_class.message('No.Such.Message') }
        .to raise_error(Ajax::Sdk::Cloud::UnknownMessageError, /No.Such.Message/)
    end
  end

  describe '.descriptor_set' do
    def files(*names) = Google::Protobuf::FileDescriptorSet.decode(described_class.descriptor_set(*names)).file.to_a

    it 'gives the data channel files with what they import, each after its imports', :aggregate_failures do
      set = files('ajax/dcp/v1/dcp.proto', 'ajax/video/v1/metadata/metadata.proto')
      names = set.map(&:name)

      expect(names).to include('ajax/dcp/v1/archive.proto', 'ajax/video/v1/types/types.proto',
                               'google/protobuf/timestamp.proto')
      expect(set.map { |file| file.dependency.to_a - names.take(names.index(file.name)) }).to all(be_empty)
      expect(names).to eq(names.uniq)
    end

    it 'loads into a pool of its own, where a data channel message encodes' do
      pool = Google::Protobuf::DescriptorPool.new
      files('ajax/dcp/v1/dcp.proto').each { pool.add_serialized_file(it.to_proto) }
      client = pool.lookup('ajax.dcp.v1.ClientMsg').msgclass

      expect(client.decode(client.encode(client.new(tag: 3, archive_pause: {}))).tag).to eq(3)
    end

    it 'raises KeyError for a file the schemas do not hold' do
      expect { described_class.descriptor_set('no/such.proto') }.to raise_error(KeyError, %r{no/such\.proto})
    end
  end
end
