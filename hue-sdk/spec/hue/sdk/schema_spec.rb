# frozen_string_literal: true

require_relative '../../../schema/generate'

RSpec.describe Hue::Sdk::Schema do
  let(:light) do
    { 'id' => 'l1', 'type' => 'light', 'owner' => { 'rid' => 'd1', 'rtype' => 'device' }, 'on' => { 'on' => true },
      'mode' => 'normal', 'future' => { 'field' => 1 } }
  end

  it 'builds a response value with its nested values', :aggregate_failures do
    value = described_class::Light.from(light)
    expect(value.on).to eq(described_class::OnFeature.new(on: true))
    expect(value.owner).to have_attributes(rid: 'd1', rtype: 'device')
  end

  it 'leaves the fields the bridge did not send nil' do
    expect(described_class::Light.from(light).dimming).to be_nil
  end

  it 'builds the values of a list' do
    device = described_class::Device.from('id' => 'd1', 'services' => [{ 'rid' => 'l1', 'rtype' => 'light' }])
    expect(device.services).to eq([described_class::ResourceIdentifier.new(rid: 'l1', rtype: 'light')])
  end

  it 'rejects a request field the app does not send' do
    expect { described_class::OnFeatureUpdate.new(of: true) }.to raise_error(ArgumentError, /unknown keyword: :of/)
  end

  it 'requires the request fields the bridge needs' do
    expect { described_class::RoomMetadataAdd.new(name: 'Kitchen') }
      .to raise_error(ArgumentError, /missing keyword: :archetype/)
  end

  it 'refuses a body whose required field is nil' do
    metadata = described_class::RoomMetadataAdd.new(name: nil, archetype: 'kitchen')
    expect { metadata.to_body }.to raise_error(ArgumentError, /name/)
  end

  it 'turns a request into a body without its empty fields' do
    update = described_class::LightUpdate.new(on: described_class::OnFeatureUpdate.new(on: false),
                                              dimming: described_class::DimmingFeatureUpdate.new(brightness: 40))
    expect(update.to_body).to eq(on: { on: false }, dimming: { brightness: 40 })
  end

  it 'turns the values of a list into bodies' do
    room = described_class::RoomAdd.new(
      metadata: described_class::RoomMetadataAdd.new(name: 'Kitchen', archetype: 'kitchen'),
      children: [described_class::ResourceIdentifierAdd.new(rid: 'd1', rtype: 'device')]
    )
    expect(room.to_body[:children]).to eq([{ rid: 'd1', rtype: 'device' }])
  end

  it 'reads and writes a table of values, its keys left as they are', :aggregate_failures do
    table = { String => described_class::OnFeatureUpdate }
    values = described_class::Value.load(table, 'a' => { 'on' => true })
    expect(values['a']).to be_a(described_class::OnFeatureUpdate)
    expect(described_class::Value.dump(values)).to eq('a' => { on: true })
  end

  it 'makes every field of a change optional, nested classes included', :aggregate_failures do
    value = described_class::LightChange.from('dimming' => { 'brightness' => 60.0 })
    expect(value.dimming).to be_a(described_class::DimmingFeatureChange)
    expect(value.dimming.brightness).to eq(60.0)
    expect(value.on).to be_nil
  end

  it 'has a change class for every resource type' do
    expect(described_class::CHANGES.keys).to match_array(described_class::RESPONSES.keys)
  end

  it 'keeps a changed configuration a hash, without a script id to read it by' do
    value = described_class::BehaviorInstanceChange.from('configuration' => { 'where' => [] })
    expect(value.configuration).to eq('where' => [])
  end

  it 'types the changed state of an automation' do
    value = described_class::BehaviorInstanceChange.from('state' => { 'timer_state' => 'paused' })
    expect(value.state.timer_state).to eq('paused')
  end

  it 'gives every registered resource type a response value' do
    expect(Hue::Sdk::Models::REGISTRY.keys - described_class::RESPONSES.keys).to be_empty
  end

  it 'matches what schema/generate.rb writes from its data' do
    root = File.expand_path('../../..', __dir__)
    files = SchemaGenerator.load(root).files
    expect(files.to_h { |path, _| [path, File.read(File.join(root, path))] }).to eq(files)
  end

  it 'writes a class in the file of its kind, whichever kind holds it' do
    files = SchemaGenerator.load(File.expand_path('../../..', __dir__)).files
    expect(files['lib/hue/sdk/schema/responses.rb']).not_to include('BehaviorState = Data.define')
  end
end
