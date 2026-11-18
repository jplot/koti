# frozen_string_literal: true

RSpec.describe 'Api::Plans' do
  let(:studio) { JSON.parse(Rails.root.join('../catalog/examples/studio.json').read) }

  context 'when signed in' do
    before do
      User.create!(email_address: 'ana@example.test', password: 'correct horse')
      post '/api/session', params: { email_address: 'ana@example.test', password: 'correct horse' }, as: :json
    end

    it 'answers 404 when no plan was imported' do
      get '/api/plan'
      expect(response).to have_http_status(:not_found)
    end

    it 'imports then serves the plan', :aggregate_failures do
      put '/api/plan', params: studio, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(studio)
      get '/api/plan'
      expect(response.parsed_body).to eq(studio)
    end

    it 'keeps the previous plan when an import is refused', :aggregate_failures do
      put '/api/plan', params: studio, as: :json
      put '/api/plan', params: studio.merge('format' => 'x'), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors'].first).to include('`/format`')
      get '/api/plan'
      expect(response.parsed_body).to eq(studio)
    end

    it 'answers 422 to a body that is not JSON', :aggregate_failures do
      put '/api/plan', params: 'nope', headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('errors' => ['body is not JSON'])
    end
  end

  it 'answers 401 without a session', :aggregate_failures do
    get '/api/plan'
    expect(response).to have_http_status(:unauthorized)
    put '/api/plan', params: studio, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
