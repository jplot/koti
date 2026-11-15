# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Home, '#start_trial' do
  include_context 'with the Hue cloud'

  it "starts a bridge's trial with the request the app sends" do
    answer_empty
    home.start_trial('ECB5FAFFFE000001', model_id: 'BSB002')
    expect(sent).to eq(['PUT', '/security/payment/v2/home/home-1/device/experience_period/enable', 'application/json',
                        '{"device":"ECB5FAFFFE000001","model_id":"BSB002"}'])
  end

  it 'sends the bridge id upper-cased, as the app holds it' do
    answer_empty
    home.start_trial('ecb5fafffe000001', model_id: 'BSB002')
    expect(cloud.requests.last.body).to eq('{"device":"ECB5FAFFFE000001","model_id":"BSB002"}')
  end

  it 'raises ResponseError when the cloud refuses it' do
    answer({}, 409)
    expect { home.start_trial('ECB5FAFFFE000001', model_id: 'BSB002') }
      .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 409)))
  end
end
