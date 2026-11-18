# frozen_string_literal: true

RSpec.describe 'GET /up' do
  it 'answers 200 once Rails has booted' do
    get '/up'
    expect(response).to have_http_status(:ok)
  end
end
