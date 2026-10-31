# frozen_string_literal: true

RSpec.describe Miele::Sdk::Oven do
  subject(:oven) { described_class.new('127.0.0.1') }

  let(:fab) { '000123456789' }
  let(:leaves) { {} }
  let(:fake) do
    served = leaves
    FakeAppliance.start do |request|
      case request
      in { verb: 'GET', path: '/Devices/' } then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in { verb: 'GET', path: %r{/DOP2/(.+)\z} } then [200, {}, served.fetch(Regexp.last_match(1))]
      else [204, {}, '']
      end
    end
  end

  before { connect_to(fake) }

  after { fake.stop }

  def dop2_paths = fake.requests.map(&:path).grep(/DOP2/).map { it.delete_prefix("/Devices/#{fab}/DOP2/") }

  def temperature(value) = { 6 => dop2_field(:struct, { 4 => dop2_field(:u16, value) }) }

  it 'reads the oven DeviceContext without an index, as the app observes it', :aggregate_failures do
    leaves['1/1585'] = dop2_leaf(1, 1585, { 9 => dop2_field(:e16_array, [1, 2]) })
    expect(oven.context.supported_user_requests).to eq(%i[req_start req_stop])
    expect(oven.supported_requests).to eq([1, 2])
    expect(dop2_paths).to eq(%w[1/1585 1/1585])
  end

  it 'reads the target temperature in °C from 1/1574' do
    leaves['1/1574?idx1=0&idx2=1'] = dop2_leaf(1, 1574, { 4 => dop2_field(:struct, temperature(18_000)) }, idx2: 1)
    expect(oven.target_temperature).to eq(180.0)
  end

  it 'reads nil for a parameter the context lacks' do
    leaves['1/1574?idx1=0&idx2=1'] = dop2_leaf(1, 1574, {}, idx2: 1)
    expect(oven.target_temperature).to be_nil
  end

  it 'lists the own programs along the chain of indexes, as the app does', :aggregate_failures do
    leaves['1/109?idx1=0&idx2=1'] = dop2_leaf(1, 109, {}, idx1: 0, idx2: 5)
    leaves['1/109?idx1=5&idx2=1'] = dop2_leaf(1, 109, {}, idx1: 5, idx2: 7)
    leaves['1/109?idx1=7&idx2=1'] = dop2_leaf(1, 109, {}, idx1: 7, idx2: 7)
    expect(oven.own_programs.size).to eq(3)
    expect(dop2_paths).to eq(%w[1/109?idx1=0&idx2=1 1/109?idx1=5&idx2=1 1/109?idx1=7&idx2=1])
  end

  it 'reads the steps of the running own program, one per index from 0' do
    leaves['2/213?idx1=0&idx2=1'] = dop2_leaf(2, 213, { 1 => dop2_field(:u8, 2) }, idx2: 1)
    2.times { leaves["2/214?idx1=#{it}&idx2=1"] = dop2_leaf(2, 214, {}, idx1: it, idx2: 1) }
    expect(oven.program_steps.last.size).to eq(2)
  end
end
