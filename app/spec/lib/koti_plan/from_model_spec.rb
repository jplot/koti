# frozen_string_literal: true

RSpec.describe KotiPlan::FromModel do
  let(:model) { JSON.parse(file_fixture('models/flat.json').read) }
  let(:document) { described_class.new(model, 'Logement').document }
  let(:level) { document['levels'].first }

  it('produces a valid plan') { expect(KotiPlan.errors(document)).to eq([]) }

  it 'names the level and takes its height from the tallest ceiling' do
    expect(level.slice('id', 'name', 'elevation', 'height'))
      .to eq('id' => 'logement', 'name' => 'Logement', 'elevation' => 0, 'height' => 240)
  end

  it 'turns a wall rectangle into a footprint' do
    expect(level['walls'][0]).to eq('id' => 'w1', 'footprint' => [[0, 0], [300, 0], [300, 20], [0, 20]])
  end

  it 'places an x-axis door on its wall axis' do
    expect(level['openings'][0]).to include('kind' => 'door', 'name' => "Porte d'exemple", 'from' => [100, 50],
                                            'to' => [180, 50], 'depth' => 20, 'sill' => 0, 'head' => 204,
                                            'hinge' => 'from', 'swing' => 1)
  end

  it 'flips the swing of a y-axis door and keeps its head' do
    expect(level['openings'][1]).to include('from' => [290, 60], 'to' => [290, 140], 'head' => 200, 'swing' => -1)
  end

  it 'gives a window its default sill and head, and no hinge' do
    expect(level['openings'][2]).to eq('id' => 'fenetre-a', 'kind' => 'window', 'name' => 'Fenêtre',
                                       'from' => [10, 80], 'to' => [10, 160], 'depth' => 20,
                                       'sill' => 50, 'head' => 215)
  end

  it 'puts a measured window height above the default sill' do
    expect(level['openings'][4]).to include('sill' => 50, 'head' => 210)
  end

  it 'gives a sliding bay the door head' do
    expect(level['openings'][3]).to include('kind' => 'sliding', 'sill' => 0, 'head' => 204)
  end

  it 'keeps a room and its ceiling' do
    expect(level['rooms'][0]).to eq('id' => 'salon', 'name' => 'Salon', 'ceiling' => 240, 'finish' => 'parquet',
                                    'label' => [150, 120], 'outline' => [[[20, 20], [280, 20], [280, 200], [20, 200]]])
  end

  it 'leaves out the ceiling of a room without hsp' do
    expect(level['rooms'][1]).not_to have_key('ceiling')
  end

  it 'falls back to 250 when no room has a ceiling' do
    model['rooms'].each { it['hsp'] = nil }
    expect(level['height']).to eq(250)
  end
end
