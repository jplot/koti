# frozen_string_literal: true

require_relative '../../../schema/extract/match'

RSpec.describe Schema::Extract::Match do
  subject(:match) { described_class.new(app, capture) }

  let(:app) do
    field = { 'type' => 'int32', 'nullable' => true }
    { 'Rest.WideDto' => { 'fields' => %w[DeviceType AppSupport Extra More].to_h { [it, field] } },
      'Rest.IdentDto' => { 'fields' => %w[DeviceType AppSupport Extra].to_h { [it, field] } },
      'Rest.ModeDto' => { 'fields' => %w[DeviceType Mode].to_h { [it, field] } },
      'Rest.TypeDto' => { 'fields' => { 'DeviceType' => field } },
      'Rest.LinkDto' => { 'fields' => { 'href' => field } } }
  end
  let(:capture) do
    { 'hob' => { '/Devices/{fab}/Ident' => { 'DeviceType' => 13, 'AppSupport' => 1 },
                 '/Devices/{fab}/SuperVision' => { 'error' => 'Miele::Sdk::NotFoundError' },
                 '/Devices/' => { '000123' => { 'href' => '000123/' } } },
      'hood' => { '/Devices/{fab}/Ident' => { 'DeviceType' => 18 } } }
  end

  it 'ranks three app classes holding the most keys of each resource, then the fewest others' do
    expect(match.best['/Devices/{fab}/Ident'])
      .to eq([['Rest.IdentDto', 2, 1], ['Rest.WideDto', 2, 2], ['Rest.TypeDto', 1, 0]])
  end

  it 'reads the entries of a resource keyed by number as one resource' do
    expect(match.best.slice('/Devices/', '/Devices/ <n>')).to eq('/Devices/ <n>' => [['Rest.LinkDto', 1, 0]])
  end

  it 'leaves out the resources an appliance answered with an error' do
    expect(match.best.keys).not_to include('/Devices/{fab}/SuperVision')
  end

  it 'prints each resource with its keys and best classes' do
    expect(match.report).to include(%(/Devices/{fab}/Ident ["AppSupport", "DeviceType"]\n    2/2 +1 Rest.IdentDto))
  end
end
