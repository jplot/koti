# frozen_string_literal: true

# A logged-in account whose cloud is a FakeCloud answering what the example pushes to +answers+, and its home
# +home-1+.
RSpec.shared_context 'with the Hue cloud' do
  let(:answers) { [] }
  let(:cloud) { FakeCloud.start { |request| answers.shift unless request.path.start_with?('/.well-known') } }
  let(:home) { Hue::Sdk::Secure.home('home-1') }

  before do
    token = Hue::Sdk::Secure::Token.new(value: 'jwt-1', refresh: 'refresh-1', created_at: Time.now,
                                        expires_at: Time.now + 3600)
    Hue::Sdk::Secure.configure do |config|
      config.client_id = 'test-client'
      config.token = token.to_json
      config.login_url = cloud.url
      config.api_url = cloud.url
    end
  end

  after { cloud.stop }

  def answer(value, status = 200) = answers.push(FakeCloud.json(value, status))

  def answer_empty = answers.push([204, {}, ''])

  def sent = cloud.requests.last.then { [it.verb, it.path, it.headers['content-type'], it.body] }
end
