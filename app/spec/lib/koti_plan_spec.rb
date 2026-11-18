# frozen_string_literal: true

RSpec.describe KotiPlan do
  let(:studio) { JSON.parse(Rails.root.join('../catalog/examples/studio.json').read) }
  let(:level) { studio['levels'].first }

  it('accepts the studio') { expect(described_class.errors(studio)).to eq([]) }

  it 'is itself a valid 2020-12 schema' do
    expect(JSONSchemer.draft202012.valid?(JSON.parse(described_class::SCHEMA_PATH.read))).to be(true)
  end

  it 'refuses another format' do
    expect(described_class.errors(studio.merge('format' => 'x'))).to include(a_string_including('`/format`'))
  end

  it 'refuses a door without swing' do
    level['openings'][0].delete('swing')
    expect(described_class.errors(studio)).to include(a_string_including('`/levels/0/openings/0`'))
  end

  it 'refuses a two-point ring' do
    level['walls'][0]['footprint'] = [[0, 0], [250, 0]]
    expect(described_class.errors(studio)).to include(a_string_including('`/levels/0/walls/0/footprint`'))
  end

  it 'refuses an unknown property' do
    level['walls'][0]['colour'] = 'white'
    expect(described_class.errors(studio)).to include(a_string_including('`/levels/0/walls/0/colour`'))
  end

  it 'refuses a duplicate id in a level' do
    level['walls'][1]['id'] = 'w1'
    expect(described_class.errors(studio)).to include('value at `/levels/0/walls/1/id` repeats the id w1')
  end

  it 'refuses a duplicate level id' do
    studio['levels'] << level.merge('name' => 'Copie')
    expect(described_class.errors(studio)).to include('value at `/levels/1/id` repeats the id studio')
  end

  it 'refuses a sill at or above the head' do
    level['openings'][1]['sill'] = 215
    expect(described_class.errors(studio))
      .to include('value at `/levels/0/openings/1/sill` must be below the head (215)')
  end

  it 'refuses a head above the level' do
    level['openings'][1]['head'] = 260
    expect(described_class.errors(studio))
      .to include('value at `/levels/0/openings/1/head` must not exceed the level height (250)')
  end

  it 'refuses a document that is not an object' do
    expect(described_class.errors([])).to include(a_string_including('root'))
  end
end
