# frozen_string_literal: true

RSpec.describe Miele::Sdk::Hood do
  subject(:hood) { described_class.new('127.0.0.1', ident:) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 18, 'ProtocolVersion' => 2) }
  let(:plus) do
    { 'available' => true, 'activated' => false, 'availableSourceDeviceIds' => %w[000111222333 000444555666],
      'sourceDeviceIds' => [] }
  end
  let(:color_flow) { [200, {}, '{"active":false,"intervalDurationSeconds":10}'] }
  let(:fake) do
    services = JSON.generate('ConnectivityPlus' => plus)
    flow = color_flow
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/services\z} } then [200, {}, services]
      in { verb: 'GET', path: %r{/ColorFlow\z} } then flow
      else [200, {}, '{}']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def written = fake.requests.reject { it.verb == 'GET' }.map { [it.verb, it.path, JSON.parse(it.body)] }

  it 'reads Con@ctivity Plus from services' do
    expect(hood.connectivity_plus).to eq(described_class::ConnectivityPlus.new(
                                           available: true, activated: false,
                                           available_sources: %w[000111222333 000444555666], sources: []
                                         ))
  end

  it 'switches Con@ctivity Plus on with the hobs it follows' do
    hood.configure_connectivity_plus(activated: true, sources: %w[000111222333])
    expect(written).to eq([['PUT', "/Devices/#{fab}/services/ConnectivityPlus",
                            { 'activated' => true, 'sourceDeviceIds' => %w[000111222333] }]])
  end

  it 'shows an appliance under Con@ctivity One, its Signal left out as the app leaves it' do
    hood.supervise('000111222333', show: true)
    expect(written).to eq([['PUT', "/Devices/#{fab}/SuperVision/000111222333", { 'Show' => true }]])
  end

  it 'sets ColorFlow with its interval in seconds, refusing another interval', :aggregate_failures do
    hood.configure_color_flow(active: true, interval: 20)
    expect { hood.configure_color_flow(active: true, interval: 15) }.to raise_error(ArgumentError)
    expect(written).to eq([['PUT', "/Devices/#{fab}/ColorFlow", { 'active' => true, 'intervalDurationSeconds' => 20 }]])
  end

  context 'when the hood has no ColorFlow' do
    let(:color_flow) { [404, {}, ''] }

    it 'refuses ColorFlow on a hood that has none' do
      expect { hood.configure_color_flow(active: true) }.to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end

  context 'when the hood does not offer Con@ctivity Plus' do
    let(:plus) { { 'available' => false } }

    it 'refuses to switch it' do
      expect { hood.configure_connectivity_plus(activated: true, sources: []) }
        .to raise_error(Miele::Sdk::ActionUnavailableError)
    end
  end
end
