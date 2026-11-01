# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1', ident:, sleeper: ->(seconds) { naps << seconds }) }

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 13, 'ProtocolVersion' => 4) }
  let(:naps) { [] }
  let(:resources) do
    shown = { 7 => dop2_field(:struct, { 10 => dop2_field(:e8, 5), 28 => dop2_field(:e16, 13) }) }
    power = { 15 => dop2_field(:struct, { 1 => dop2_field(:u8, 9), 2 => dop2_field(:u8, 0x7F) }) }
    { put: [[500, {}, '']], 'State' => [JSON.generate('Status' => 3, 'RemoteEnable' => [15, 0, 0])],
      'DOP2/1/1585' => [dop2_leaf(1, 1585, shown)],
      'DOP2/1/1574?idx1=0&idx2=1' => [dop2_leaf(1, 1574, shown.merge(4 => dop2_field(:struct, power)), idx2: 1)] }
  end
  let(:fake) do
    served = resources
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: } then answer(served.fetch(path.delete_prefix("/Devices/#{fab}/")))
      else served[:put].shift || [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def answer(bodies)
    body = bodies.size > 1 ? bodies.shift : bodies.first
    body.is_a?(Array) ? body : [200, {}, body]
  end

  def infos(*ids)
    shown = ids.map { { 1 => dop2_field(:e16, it) } }
    dop2_leaf(1, 131, { 1 => dop2_field(:struct_array, shown) }, idx2: 1)
  end

  def notifications(*answers) = resources['DOP2/1/131?idx1=0&idx2=1'] = [infos, *answers]

  def written = fake.requests.select { it.verb == 'PUT' }.map { it.path.delete_prefix("/Devices/#{fab}/") }

  it 'takes a 500 as done once 1/131 shows info 14, polled every 3 s as the app does', :aggregate_failures do
    notifications(infos(2), infos(14))
    expect { oven.microwave_power = 0x10 }.not_to raise_error
    expect(naps).to eq([3])
    expect(written).to eq(['DOP2/2/1577'])
  end

  it 'raises the 500 when info 14 does not show within the 6 s the app waits', :aggregate_failures do
    notifications(infos)
    expect { oven.microwave_power = 0x10 }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
    expect(naps).to eq([3])
  end

  it 'raises the 500 when 1/131 refuses with a 4xx, as the app rethrows the write error' do
    notifications([404, {}, ''])
    expect { oven.microwave_power = 0x10 }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 500')
  end

  it 'raises another refusal of the write at once', :aggregate_failures do
    notifications
    resources[:put] = [[503, {}, '']]
    expect { oven.microwave_power = 0x10 }.to raise_error(Miele::Sdk::ResponseError, 'appliance answered 503')
    expect(fake.requests.count { it.path.include?('DOP2/1/131') }).to eq(1)
  end
end
