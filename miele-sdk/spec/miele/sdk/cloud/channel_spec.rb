# frozen_string_literal: true

RSpec.describe Miele::Sdk::Cloud::Channel do
  subject(:channel) { described_class.new(Miele::Sdk::Cloud::Session.new(organization)) }

  let(:fab) { '000123456789' }
  let(:answers) { [] }
  let(:cloud) do
    FakeCloud.start do |request|
      case request.path
      when '/V2/AppTokenRefresh' then FakeCloud.json(appToken: 'renewed', appTokenValidity: Time.now.to_i + 3600)
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

  it 'renews and retries once on 401', :aggregate_failures do
    answers.push([401, {}, ''], FakeCloud.json({}))
    channel.request(:get, "/Devices/#{fab}/State")
    expect(seen("/V2/Devices/#{fab}/State").map { it.headers['authorization'] })
      .to eq(['appToken saved', 'appToken renewed'])
  end

  context 'when two requests in flight get 401 with the same token' do
    let(:cloud) do
      FakeCloud.start(threaded: true) do |request|
        case request.path
        when '/V2/AppTokenRefresh' then FakeCloud.json(appToken: 'renewed', appTokenValidity: Time.now.to_i + 3600)
        when %r{/V2/Devices/(\d+)/State}
          next FakeCloud.json({}) unless request.headers['authorization'] == 'appToken saved'

          sleep 0.5 if Regexp.last_match(1) == '2'
          [401, {}, '']
        end
      end
    end

    it 'renews the token once' do
      %w[1 2].map { |id| Thread.new { channel.request(:get, "/Devices/#{id}/State") } }.each(&:join)
      expect(seen('/V2/AppTokenRefresh').size).to eq(1)
    end
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

  it 'reads the household key from the cloud' do
    answers << FakeCloud.json([{ groupId: '0123456789ABCDEF', groupKey: 'AB' * 64, devices: [] }])
    expect(channel.group).to eq(['0123456789ABCDEF', 'AB' * 64])
  end
end
