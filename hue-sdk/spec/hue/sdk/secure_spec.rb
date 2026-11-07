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

  describe '.auto_responses' do
    include_context 'with the Hue cloud'

    before { described_class.configure { it.auto_responses_url = cloud.url } }

    it 'reads the automatic responses a doorbell may play, with the token', :aggregate_failures do
      answer('responses' => { 'en' => [{ 'id' => 'r-1', 'path' => 'r-1.mp3' }] },
             'categories' => [{ 'id' => 'c-1', 'name' => 'Away', 'type' => 'standard' }])
      read = described_class.auto_responses
      expect(cloud.requests.last.then { [it.verb, it.path, it.headers['authorization']] })
        .to eq(['GET', '/automatic_response/manifest.json', 'Bearer jwt-1'])
      expect([read.categories.first.name, read.responses['en'].first['path']]).to eq(%w[Away r-1.mp3])
    end
  end
end
