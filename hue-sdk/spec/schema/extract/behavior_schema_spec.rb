# frozen_string_literal: true

require_relative '../../../schema/extract/behaviors'

RSpec.describe Schema::Extract::BehaviorSchema do
  subject(:schema) do
    described_class.compose(scripts: { 'scripts' => { 'id' => {} }, 'classes' => { 'A' => {} } },
                            classes: { 'B' => {} })
  end

  it 'gathers the scripts and classes with the requests and the types of hue.json it changes', :aggregate_failures do
    expect(schema['scripts']).to include('id' => {})
    expect(schema['classes'].keys).to include('A', 'B', 'BehaviorInstanceAdd', 'BehaviorInstanceUpdate',
                                              'BehaviorTrigger')
    expect(schema['resources']).to eq('behavior_instance' => { 'update' => 'BehaviorInstanceUpdate',
                                                               'create' => 'BehaviorInstanceAdd' })
    expect(schema['overrides']['BehaviorInstance']['state']).to eq('type' => { 'class' => 'BehaviorState' })
  end

  it 'requires what the app always sends to create an automation' do
    required = schema['classes']['BehaviorInstanceAdd']['fields'].select { |_, field| field['required'] }.keys
    expect(required).to contain_exactly('script_id', 'enabled', 'configuration', 'metadata')
  end

  it 'offers only what the app sends to create an automation' do
    expect(schema['classes']['BehaviorInstanceAdd']['fields'].keys)
      .to contain_exactly('script_id', 'enabled', 'configuration', 'metadata', 'migrated_from')
  end

  it 'gives an accessory script the class the app reads it with' do
    expect(schema['scripts']['bba79770-19f1-11ec-9621-0242ac130002'])
      .to eq('name' => 'motion_sensor', 'configuration' => 'AccessoryBehaviorMotionSensorConfiguration')
  end

  it 'describes an action as a name of the app, or a hash to recall a scene' do
    expect(schema['classes']['AccessoryActionValue']['fields']['action'])
      .to include('type' => 'Object', 'values' => a_collection_including('all_off', 'home_off', 'dim_alternate'))
  end

  it 'triggers an automation with a start or a stop' do
    expect(schema['classes']['BehaviorTrigger']['fields'].keys).to contain_exactly('start', 'stop')
  end
end
