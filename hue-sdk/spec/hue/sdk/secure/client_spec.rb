# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Client do
  subject(:client) { described_class.new(session) }

  let(:answers) { [] }
  let(:cloud) { FakeCloud.start { |request| answers.shift unless request.path.start_with?('/.well-known') } }
  let(:session) do
    token = Hue::Sdk::Secure::Token.new(value: 'jwt-1', refresh: 'refresh-1', created_at: Time.now,
                                        expires_at: Time.now + 3600)
    Hue::Sdk::Secure.configure { it.token = token.to_json }
    Hue::Sdk::Secure::Session.new
  end

  before do
    Hue::Sdk::Secure.configure do |config|
      config.client_id = 'test-client'
      config.login_url = cloud.url
      config.api_url = cloud.url
    end
  end

  after { cloud.stop }

  def answer(status, value = {}, headers = {}) = answers.push(FakeCloud.json(value, status, headers))

  it 'sends the token and its own name', :aggregate_failures do
    answer(200, nil)
    client.get('security/arm-manager/v1/home/home-1/arm/state')
    request = cloud.requests.last
    expect([request.verb, request.path]).to eq(['GET', '/security/arm-manager/v1/home/home-1/arm/state'])
    expect(request.headers.values_at('authorization', 'user-agent'))
      .to eq(['Bearer jwt-1', "hue-sdk/#{Hue::Sdk::VERSION}"])
  end

  it 'gives status, body and headers', :aggregate_failures do
    answer(200, { 'data' => [] }, 'x-cursor' => 'next-1')
    path = 'data/timeline/security/home-1/range'
    response = client.get(path, query: { limit: 10 }, headers: { 'x-cursor' => 'first' })
    expect([response.status, response.body, response.headers['x-cursor']]).to eq([200, { 'data' => [] }, 'next-1'])
    expect(cloud.requests.last.then { [it.path, it.headers['x-cursor']] })
      .to eq(['/data/timeline/security/home-1/range?limit=10', 'first'])
  end

  it 'sends a body as JSON' do
    answers.push([204, {}, ''])
    client.put('security/arm-manager/v1/home/home-1/arm/state', body: { arm_state: 'disarmed' })
    expect(cloud.requests.last.then { [it.verb, it.headers['content-type'], it.body] })
      .to eq(['PUT', 'application/json', '{"arm_state":"disarmed"}'])
  end

  it 'names JSON on every security request and on a body only for the data API' do
    3.times { answer(200) }
    client.get('security/arm-manager/v1/home/home-1/arm')
    client.get('data/timeline/security/home-1/range')
    client.post('data/timeline/security/home-1/delete', body: {})
    expect(cloud.requests.last(3).map { it.headers['content-type'] })
      .to eq(['application/json', nil, 'application/json'])
  end

  it 'gives an empty body as nil' do
    answers.push([204, {}, ''])
    expect(client.delete('security/arm-manager/v1/home/home-1/arm').body).to be_nil
  end

  it 'reaches an absolute address' do
    answer(200, {})
    client.post("#{cloud.url}/automatic_response/manifest.json")
    expect(cloud.requests.last.path).to eq('/automatic_response/manifest.json')
  end

  {
    401 => Hue::Sdk::AuthenticationError, 403 => Hue::Sdk::AuthenticationError, 404 => Hue::Sdk::NotFoundError,
    429 => Hue::Sdk::RateLimitError, 207 => Hue::Sdk::ResponseError, 500 => Hue::Sdk::ResponseError,
    521 => Hue::Sdk::ResponseError
  }.each do |status, error|
    it "answers #{status} with #{error.name.split('::').last}" do
      answer(status)
      expect { client.get('security/x') }.to raise_error(error)
    end
  end

  it 'gives the status and the messages of the data API in a ResponseError' do
    answer(500, errors: [{ code: 'internal', message: 'something broke' }])
    expect { client.get('data/x') }.to raise_error(
      an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 500, errors: ['something broke'],
                                                                    message: 'Hue cloud answered 500: something broke'))
    )
  end

  def raised
    yield
  rescue Hue::Sdk::Error => e
    e
  end

  it 'never puts the token in an error', :aggregate_failures do
    answer(500, errors: [{ code: 'internal', message: 'no' }])
    refused = raised { client.get('data/x') }
    cloud.stop
    unreachable = raised { client.get('data/x') }
    expect([refused, unreachable].map(&:class)).to eq([Hue::Sdk::ResponseError, Hue::Sdk::ConnectionError])
    expect([refused, unreachable].flat_map { [it.message, it.inspect] }.grep(/jwt-1|refresh-1/)).to be_empty
  end
end
