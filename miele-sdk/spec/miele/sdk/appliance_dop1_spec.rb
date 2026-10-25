# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) { Miele::Sdk.appliance('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:dop1_answer) { [200, {}, '{"Response":"12011100009C4A000000030000000000000005"}'] }
  let(:fake) do
    FakeAppliance.start do |request|
      request.verb == 'POST' ? dop1_answer : [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  it 'posts the request to /DOP/', :aggregate_failures do
    appliance.fan_level = 2
    expect(fake.requests.last).to have_attributes(verb: 'POST', path: "/Devices/#{fab}/DOP/", verified: true)
    expect(JSON.parse(fake.requests.last.body)).to eq('Request' => '8E01020000FF0200')
  end

  it 'reads a hood setting' do
    expect(appliance.setting(40_010)).to eq(3)
  end

  it 'sends each hood write', :aggregate_failures do
    appliance.fan_run_on_time = 5
    appliance.main_light = true
    appliance.write_setting(40_010, 0)
    requests = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Request') }
    expect(requests).to eq(%w[8E0602000005 14000200020104000000000000FFFF0000 12010200009C4A00000000])
  end

  context 'when the hood answers 400' do
    let(:dop1_answer) { [400, {}, ''] }

    it 'treats a 400 answer to a hood write as done' do
      expect { appliance.fan_level = 0 }.not_to raise_error
    end
  end
end
