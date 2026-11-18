# frozen_string_literal: true

RSpec.describe 'The built front' do
  let(:public_path) { Pathname(Dir.mktmpdir('front', Rails.root.join('tmp'))) }

  before do
    public_path.join('index.html').write('<!doctype html><title>koti</title>')
    allow(Rails).to receive(:public_path).and_return(public_path)
  end

  after { FileUtils.remove_entry(public_path) }

  it 'serves the front at the root without a session', :aggregate_failures do
    get '/'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('<title>koti')
  end

  it 'serves the front on a client route' do
    get '/login'
    expect(response.body).to include('<title>koti')
  end

  it 'leaves unknown api paths to the api', :aggregate_failures do
    get '/api/nope'
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('<title>koti')
  end

  it 'answers 404 when the front is not built' do
    Rails.public_path.join('index.html').delete
    get '/'
    expect(response).to have_http_status(:not_found)
  end
end
