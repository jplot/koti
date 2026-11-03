# frozen_string_literal: true

require_relative '../../../schema/extract/behaviors'

RSpec.describe Schema::Extract::BehaviorSchema do
  subject(:schema) do
    described_class.compose(scripts: { 'scripts' => { 'id' => {} }, 'classes' => { 'A' => {} } },
                            classes: { 'B' => {} })
  end

  it 'gathers the scripts and classes with the requests and the types of hue.json it changes', :aggregate_failures do
    expect(schema['scripts']).to eq('id' => {})
    expect(schema['classes'].keys).to include('A', 'B', 'BehaviorInstanceAdd', 'BehaviorInstanceUpdate',
                                              'BehaviorTrigger')
    expect(schema['resources']).to eq('behavior_instance' => { 'update' => 'BehaviorInstanceUpdate',
                                                               'create' => 'BehaviorInstanceAdd' })
    expect(schema['overrides']['BehaviorInstance']['state']).to eq('type' => { 'class' => 'BehaviorState' })
  end

  it 'requires what the app always sends to create an automation' do
    required = schema['classes']['BehaviorInstanceAdd']['fields'].select { |_, field| field['required'] }.keys
    expect(required).to contain_exactly('script_id', 'enabled', 'configuration')
  end

  it 'triggers an automation with a start or a stop' do
    expect(schema['classes']['BehaviorTrigger']['fields'].keys).to contain_exactly('start', 'stop')
  end
end
