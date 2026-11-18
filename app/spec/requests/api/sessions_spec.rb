# frozen_string_literal: true

RSpec.describe 'Api::Sessions' do
  let(:user) { User.create!(email_address: 'ana@example.test', password: 'correct horse') }

  def sign_in(password: 'correct horse')
    post '/api/session', params: { email_address: user.email_address, password: }, as: :json
  end

  it 'opens a session and sets an httponly signed cookie', :aggregate_failures do
    sign_in
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq('email_address' => 'ana@example.test')
    expect(response.headers['set-cookie']).to include('session_id=').and include('httponly')
  end

  it 'refuses a wrong password with 401', :aggregate_failures do
    sign_in(password: 'wrong')
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'invalid_credentials')
  end

  it 'answers 429 after 10 attempts within 3 minutes', :aggregate_failures do
    10.times { sign_in(password: 'wrong') }
    sign_in
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'rate_limited')
  end

  it 'tells who is signed in', :aggregate_failures do
    sign_in
    get '/api/session'
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('email_address' => 'ana@example.test')
  end

  it 'answers 401 to GET without a session' do
    get '/api/session'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'closes the session', :aggregate_failures do
    sign_in
    delete '/api/session'
    expect(response).to have_http_status(:no_content)
    get '/api/session'
    expect(response).to have_http_status(:unauthorized)
    expect(Session.count).to eq(0)
  end
end
