# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Cloud::Schemas do
  describe '.rpc' do
    it 'knows the login method is unary with its request' do
      rpc = described_class.rpc(
        '/systems.ajax.api.ecosystem.v3.mobilegwsvc.service.login_by_password.LoginByPasswordService/execute'
      )

      expect(rpc).to have_attributes(
        type: :unary,
        request: 'systems.ajax.api.ecosystem.v3.mobilegwsvc.service.login_by_password.LoginByPasswordRequest'
      )
    end

    it 'tells arming a space apart from arming it to night mode', :aggregate_failures do
      arm = described_class.rpc('/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm')
      night = described_class.rpc('/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/armToNightMode')

      expect(arm.request).to eq('systems.ajax.api.mobile.v2.space.security.ArmSpaceRequest')
      expect(night.request).to eq('systems.ajax.api.mobile.v2.space.security.ArmSpaceToNightModeRequest')
    end

    it 'raises UnknownMethodError for a path it does not know' do
      expect { described_class.rpc('/Nope/nope') }
        .to raise_error(Ajax::Sdk::Cloud::UnknownMethodError, %r{/Nope/nope})
    end
  end

  describe '.message' do
    it 'decodes a LiteSpace round-trip from the shipped schemas', :aggregate_failures do
      full = 'systems.ajax.api.mobile.v2.common.space.LiteSpace'
      codec = Ajax::Sdk::Protobuf::Codec.new(described_class.registry)

      bytes = codec.encode(full, { id: 'space-1', new_notifications_count: 7 })

      expect(described_class.message(full).full_name).to eq(full)
      expect(codec.decode(full, bytes)).to eq(id: 'space-1', new_notifications_count: 7)
    end
  end
end
