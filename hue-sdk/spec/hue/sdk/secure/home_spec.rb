# frozen_string_literal: true

require 'open3'

RSpec.describe Hue::Sdk::Secure::Home do
  let(:answers) { [] }
  let(:server) { FakeHomes.start { answers.shift&.call || '' } }

  before do
    token = Hue::Sdk::Secure::Token.new(value: 'jwt-1', refresh: 'refresh-1', created_at: Time.now,
                                        expires_at: Time.now + 3600)
    Hue::Sdk::Secure.configure do |config|
      config.token = token.to_json
      config.grpc_target = server.target
      config.grpc_credentials = :this_channel_is_insecure
    end
  end

  after { server.stop }

  def answer(*homes) = answers.push(-> { homes.map { FakeHomes.field(1, it) }.join })

  it 'lists the homes over gRPC', :aggregate_failures do
    answer(FakeHomes.message(1 => 'home-1', 2 => 'Maison'), FakeHomes.message(1 => 'home-2'))
    expect(Hue::Sdk::Secure.homes.map { [it.id, it.name] }).to eq([%w[home-1 Maison], ['home-2', '']])
    expect(server.calls.map { [it.request, it.metadata['authorization']] }).to eq([['', 'Bearer jwt-1']])
  end

  it 'sends no app metadata' do
    answer
    Hue::Sdk::Secure.homes
    expect(server.calls.last.metadata.keys.grep(/\Aapp-|\Adevice-id\z/)).to be_empty
  end

  it 'decodes every field the app declares' do
    answer(FakeHomes.message(1 => 'home-1', 2 => 'Maison', 3 => 2, 4 => FakeHomes.message(1 => 'bridge-1'),
                             5 => 20, 7 => 1, 8 => 13, 9 => %w[security.arm.state.view lighting.*],
                             10 => 'FR', 11 => 'Europe/Paris', 13 => true))
    expect(Hue::Sdk::Secure.homes.first).to eq(
      described_class.new(id: 'home-1', name: 'Maison', user_count: 2, max_users: 20, admin_count: 1, revision: 13,
                          permissions: %w[security.arm.state.view lighting.*], country_code: 'FR',
                          time_zone: 'Europe/Paris', security_activated: true, bridges: ['bridge-1'])
    )
  end

  it 'skips a field it does not know' do
    unknown = { 0 => "\x01", 1 => "\x00" * 8, 2 => "\x01x", 5 => "\x00" * 4 }
              .map { |type, value| FakeHomes.varint((99 << 3) | type) + value.b }
    answer(FakeHomes.message(1 => 'home-1') + unknown.join)
    expect(Hue::Sdk::Secure.homes.map(&:id)).to eq(['home-1'])
  end

  it 'turns an UNAUTHENTICATED answer into AuthenticationError' do
    answers.push(-> { raise GRPC::Unauthenticated, 'expired token' })
    expect { Hue::Sdk::Secure.homes }.to raise_error(Hue::Sdk::AuthenticationError, /expired token/)
  end

  it 'turns an unreachable server into ConnectionError, without the token' do
    Hue::Sdk::Secure.configure { it.grpc_target = '127.0.0.1:1' }
    expect { Hue::Sdk::Secure.homes }.to raise_error(Hue::Sdk::ConnectionError, satisfy { !it.include?('jwt-1') })
  end

  it 'names a home by its id, without a request', :aggregate_failures do
    expect(Hue::Sdk::Secure.home('home-1')).to have_attributes(id: 'home-1', name: nil, bridges: nil)
    expect(server.calls).to be_empty
  end

  describe 'without the grpc gem' do
    it 'loads Hue Secure and names a home' do
      lib = File.expand_path('../../../../lib', __dir__)
      script = "require 'hue/sdk/secure'; Hue::Sdk::Secure.home('home-1'); print defined?(GRPC).inspect"
      output, = Open3.capture2(RbConfig.ruby, '-I', lib, '-e', script)
      expect(output).to eq('nil')
    end

    it 'asks for grpc when listing' do
      allow(described_class).to receive(:require).with('grpc').and_raise(LoadError)
      expect { Hue::Sdk::Secure.homes }.to raise_error(Hue::Sdk::Error, /gem 'grpc'/)
    end
  end
end
