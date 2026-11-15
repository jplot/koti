# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Miele::Sdk::Cloud::Channel do
  subject(:channel) { described_class.new(Miele::Sdk::Cloud::Session.new(organization)) }

  let(:fab) { '000123456789' }
  let(:answers) { [] }
  let(:cloud) do
    FakeCloud.start do |request|
      case request.path
      when %r{\A/V2/} then answers.shift || FakeCloud.json({})
      end
    end
  end

  before do
    token = Miele::Sdk::Cloud::Token.new(value: 'saved', refresh: 'saved', scheme: 'appToken',
                                         created_at: Time.now, expires_at: Time.now + 3600)
    Miele::Sdk.configure { it.cloud_token = token.to_json }
  end

  after { cloud.stop }

  def organization
    Miele::Sdk::Cloud::Locales::Organization.new(iso: 'FR', rest: cloud.url, ciam: false, ciam_endpoints: {})
  end

  def seen(path) = cloud.requests.select { it.path == path }

  it 'sends a state read to /V2 with the appToken', :aggregate_failures do
    answers << FakeCloud.json('Status' => 5)
    expect(JSON.parse(channel.request(:get, "/Devices/#{fab}/State").body)).to eq('Status' => 5)
    expect(seen("/V2/Devices/#{fab}/State").first.headers['authorization']).to eq('appToken saved')
  end

  it 'names a language, without which the cloud answers 500' do
    channel.request(:get, "/Devices/#{fab}/State")
    expect(seen("/V2/Devices/#{fab}/State").first.headers['accept-language']).to eq('en-FR')
  end

  it 'sends a DOP2 write unpadded as vnd.miele.v1+dop2' do
    bytes = ['000e0002063200000000000100010404'].pack('H*')
    channel.request(:put, "/Devices/#{fab}/DOP2/2/1586", body: bytes, kind: :dop2)
    request = seen("/V2/Devices/#{fab}/DOP2/2/1586").first
    expect([request.headers['content-type'], request.body.b]).to eq(['application/vnd.miele.v1+dop2', bytes])
  end

  it 'names the module host on a Dop1 request' do
    channel.request(:post, "/Devices/#{fab}/DOP/", body: '{"Request":"8E0101000000"}',
                                                   host: 'Miele-0000000000000000.local.')
    expect(seen("/V2/Devices/#{fab}/DOP/").first.headers['host']).to eq('Miele-0000000000000000.local')
  end

  it 'raises a 401 and keeps the token, as the app does', :aggregate_failures do
    answers << [401, {}, '']
    expect { channel.request(:put, "/Devices/#{fab}/State", body: '{"DeviceAction":2}') }
      .to raise_error(Miele::Sdk::ResponseError) { expect(it.status).to eq(401) }
    channel.request(:get, "/Devices/#{fab}/State")
    expect(seen("/V2/Devices/#{fab}/State").map { [it.verb, it.headers['authorization']] })
      .to eq([['PUT', 'appToken saved'], ['GET', 'appToken saved']])
  end

  it 'sends a request once when the cloud drops the connection, as the app does', :aggregate_failures do
    answers << :drop
    expect { channel.request(:put, "/Devices/#{fab}/State", body: '{"DeviceAction":2}') }
      .to raise_error(Miele::Sdk::ConnectionError)
    expect(seen("/V2/Devices/#{fab}/State").map(&:verb)).to eq(%w[PUT])
  end

  it "sends a DELETE without content as the app's AndroidMessageHandler does" do
    channel.request(:delete, "/Devices/#{fab}/services/AutoStart/1")
    expect(seen("/V2/Devices/#{fab}/services/AutoStart/1").first.headers.values_at('content-length', 'content-type'))
      .to eq(['0', nil])
  end

  it 'raises NotFoundError for a resource the cloud does not serve' do
    answers << [404, {}, '']
    expect { channel.request(:get, "/Devices/#{fab}/Ident") }.to raise_error(Miele::Sdk::NotFoundError)
  end

  it 'lists the account appliances with their module host' do
    answers << FakeCloud.json([{ host: 'Miele-0000000000000000.local.', groupId: '0123456789ABCDEF',
                                 devices: [{ mac: fab, ident: { 'DeviceType' => 13 }, state: { 'Status' => 1 } }] }])
    expect(channel.devices).to contain_exactly(
      have_attributes(fab:, host: 'Miele-0000000000000000.local.', ident: { 'DeviceType' => 13 })
    )
  end

  context 'when the cloud refuses the appliance list' do
    let(:file) { File.join(Dir.mktmpdir, 'token.json') }

    before do
      File.write(file, '{}')
      Miele::Sdk.configure do |config|
        config.email = 'koti@example.com'
        config.password = 'secret'
        config.token_file = file
      end
    end

    [401, 403].each do |status|
      it "logs out and forgets the token on a #{status}, as the app does", :aggregate_failures do
        answers << [status, {}, '']
        expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError) { expect(it.status).to eq(status) }
        logout = seen('/V2/Logout')
        expect(logout.map { [it.headers['authorization'], it.headers['accept-language']] })
          .to eq([['appToken saved', 'en-FR']])
        expect([channel.session.token, File.exist?(file)]).to eq([nil, false])
      end
    end

    it 'logs in again on the next request', :aggregate_failures do
      answers << [401, {}, '']
      expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError)
      channel.devices
      expect(seen('/V2/Devices').map { it.headers['authorization'] }).to eq(['appToken saved', 'appToken token-1'])
    end

    it "sends the MCS logout as JSON, as the app's ContentTypeDelegatingHandler does", :aggregate_failures do
      answers << [401, {}, '']
      expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError)
      logout = seen('/V2/Logout').first
      expect([logout.body, *logout.headers.values_at('content-type', 'accept')])
        .to eq(['{}', 'application/json; charset=utf-8', 'application/json'])
    end

    it "sends the logout once more after a 401, as the app's AuthenticationHandler does", :aggregate_failures do
      answers.push([401, {}, ''], [401, {}, ''])
      expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError)
      expect(seen('/V2/Logout').map { it.headers['authorization'] }).to eq(['appToken saved'] * 2)
    end
  end

  context 'when the cloud refuses the renewal of a token past half its life' do
    before do
      token = Miele::Sdk::Cloud::Token.new(value: 'saved', refresh: 'saved', scheme: 'appToken',
                                           created_at: Time.now - 3600, expires_at: Time.now + 60)
      Miele::Sdk.configure { it.cloud_token = token.to_json }
    end

    it "resends a refused logout with the token renewed, as the app's TokenService gives it", :aggregate_failures do
      renewed = FakeCloud.json(appToken: 'renewed', appTokenValidity: Time.now.to_i + 3600)
      answers.push([401, {}, ''], [401, {}, ''], [401, {}, ''], renewed)
      expect { channel.request(:get, "/Devices/#{fab}/State") }.to raise_error(Miele::Sdk::AuthenticationError)
      expect(seen('/V2/Logout').map { it.headers['authorization'] }).to eq(['appToken saved', 'appToken renewed'])
    end

    it 'sends no second logout when that renewal is refused too, as the app then has no token', :aggregate_failures do
      answers.push(*Array.new(5) { [401, {}, ''] })
      expect { channel.request(:get, "/Devices/#{fab}/State") }.to raise_error(Miele::Sdk::AuthenticationError)
      expect([seen('/V2/AppTokenRefresh').size, seen('/V2/Logout').size]).to eq([4, 1])
    end
  end

  context 'when two list reads in flight are refused with the same token' do
    let(:cloud) do
      FakeCloud.start(threaded: true) do |request|
        sleep 0.2
        [401, {}, ''] if request.path == '/V2/Devices'
      end
    end

    it 'logs out once', :aggregate_failures do
      channel.session.current
      readers = Array.new(2) { Thread.new { expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError) } }
      readers.each(&:join)
      expect(seen('/V2/Logout').size).to eq(1)
    end
  end

  context 'when the cloud refuses the appliance list of a CIAM account' do
    before do
      token = Miele::Sdk::Cloud::Token.new(value: 'jwt', refresh: 'refresh', scheme: 'Bearer',
                                           created_at: Time.now, expires_at: Time.now + 3600)
      Miele::Sdk.configure { it.cloud_token = token.to_json }
    end

    def organization
      Miele::Sdk::Cloud::Locales::Organization.new(iso: 'FR', rest: cloud.url, ciam: true,
                                                   ciam_endpoints: { 'logout' => "#{cloud.url}/fr/logout" })
    end

    it 'logs out of CIAM with its bearer token, then asks for a new code', :aggregate_failures do
      answers << [401, {}, '']
      expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError)
      expect(seen('/fr/logout').map { [it.verb, it.headers['authorization']] }).to eq([['POST', 'Bearer jwt']])
      expect { channel.devices }.to raise_error(Miele::Sdk::ConfigurationError, /CIAM/)
    end

    it "sends the CIAM logout without content, as the app's AndroidMessageHandler does", :aggregate_failures do
      answers << [401, {}, '']
      expect { channel.devices }.to raise_error(Miele::Sdk::ResponseError)
      expect(seen('/fr/logout').first.headers.values_at('content-length', 'content-type')).to eq(['0', nil])
    end
  end

  it 'reads the household key from the cloud' do
    answers << FakeCloud.json([{ groupId: '0123456789ABCDEF', groupKey: 'AB' * 64, devices: [] }])
    expect(channel.group).to eq(['0123456789ABCDEF', 'AB' * 64])
  end

  it 'raises NotFoundError for an account without a household key' do
    answers << FakeCloud.json([])
    expect { channel.group }.to raise_error(Miele::Sdk::NotFoundError, /no household key/)
  end
end
