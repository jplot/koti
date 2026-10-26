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

    it 'knows that arming a space is unary' do
      rpc = described_class.rpc('/systems.ajax.api.mobile.v2.space.security.SpaceSecurityService/arm')

      expect(rpc.type).to eq(:unary)
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
end
