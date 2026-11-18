# frozen_string_literal: true

RSpec.describe 'The front entry page in public/' do
  let(:index) { Rails.public_path.join('index.html') }

  around do |example|
    kept = index.read if index.exist?
    index.write('<!doctype html><title>koti</title>')
    example.run
  ensure
    kept ? index.write(kept) : index.delete
  end

  it 'makes browsers revalidate it, so an upgrade reaches them', :aggregate_failures do
    get '/'
    expect(response.body).to include('<title>koti')
    expect(response.headers['cache-control']).to eq('no-cache')
  end
end
