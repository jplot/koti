# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hood do
  subject(:appliance) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => 2) }
  let(:state) do
    extended = [*[0] * 30, 0b1000, *[0] * 42].pack('C*').unpack1('H*')
    JSON.generate('Status' => 4, 'ExtendedState' => extended)
  end
  let(:dop1_answer) { [200, {}, '{"Response":"8E011201"}'] }
  let(:fake) do
    served = state
    FakeAppliance.start do |request|
      next [200, {}, '{"Response":"12011100009C4A000000030000000000000005"}'] if request.body.include?('"12010100')
      next dop1_answer if request.verb == 'POST'

      request.path.end_with?('/State') ? [200, {}, served] : [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  it 'posts the request to /DOP/', :aggregate_failures do
    appliance.fan_level = 2
    expect(fake.requests.last).to have_attributes(verb: 'POST', path: "/Devices/#{fab}/DOP/", verified: true)
    expect(JSON.parse(fake.requests.last.body)).to eq('Request' => '8E01020000ff0200')
  end

  it 'reads a hood setting' do
    expect(appliance.setting(40_010)).to eq(3)
  end

  it 'sends each hood write', :aggregate_failures do
    appliance.fan_run_on_time = 5
    appliance.main_light = true
    appliance.write_setting(40_010, 0)
    requests = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Request') }
    expect(requests).to eq(%w[8E0602000005 14000200020104000000000000ffff0000 12010200019c4a00000000])
  end

  context 'when the hood answers 400' do
    let(:dop1_answer) { [400, {}, ''] }

    it 'raises it, as the app never takes a refused write as done', :aggregate_failures do
      expect { appliance.fan_level = 0 }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 400')
      expect { appliance.write_setting(40_010, 0) }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 400')
    end
  end

  context 'when the hood acknowledges a write with Ack 0' do
    let(:dop1_answer) { [200, {}, '{"Response":"8E011200"}'] }

    it 'raises NotAcceptedError, as the app accepts only Ack 1' do
      expect { appliance.fan_level = 0 }.to raise_error(Miele::Sdk::NotAcceptedError, 'the appliance answered Ack "00"')
    end
  end

  context 'when the hood acknowledges a write with anything but success' do
    let(:dop1_answer) { [200, {}, '{"Response":"8E011202"}'] }

    it 'raises NotAcceptedError, as the app accepts only Ack 1', :aggregate_failures do
      expect { appliance.fan_level = 0 }.to raise_error(Miele::Sdk::NotAcceptedError, 'the appliance answered Ack "02"')
      expect { appliance.fan_run_on_time = 5 }.to raise_error(Miele::Sdk::NotAcceptedError)
      expect { appliance.main_light = true }.to raise_error(Miele::Sdk::NotAcceptedError)
      expect { appliance.write_setting(40_010, 0) }.to raise_error(Miele::Sdk::NotAcceptedError)
    end
  end
end
