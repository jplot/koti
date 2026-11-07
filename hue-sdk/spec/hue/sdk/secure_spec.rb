# frozen_string_literal: true

require 'open3'

RSpec.describe Hue::Sdk::Secure do
  it 'is not loaded by the bridge SDK' do
    lib = File.expand_path('../../../lib', __dir__)
    output, = Open3.capture2(RbConfig.ruby, '-I', lib, '-e', "require 'hue/sdk'; print defined?(Hue::Sdk::Secure)")
    expect(output).to be_empty
  end

  it 'keeps one session until the settings change', :aggregate_failures do
    session = described_class.session
    expect(described_class.session).to be(session)
    described_class.configure { it.client_id = 'test-client' }
    expect(described_class.session).not_to be(session)
  end

  it 'gives a client on the session' do
    expect(described_class.client).to be_a(described_class::Client)
  end
end
