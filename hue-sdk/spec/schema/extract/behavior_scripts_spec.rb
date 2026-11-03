# frozen_string_literal: true

require_relative '../../../schema/extract/behaviors'

RSpec.describe Schema::Extract::BehaviorScripts do
  subject(:data) { described_class.new(File.join(directory, 'behaviors'), snapshot).read }

  let(:snapshot) { Schema::Extract::Snapshot.new(directory, ->(*) { [] }) }
  let(:directory) do
    blutter_output(
      'asm/x.dart' => '',
      'pp.txt' => <<~POOL,
        [pp+0x10] Map<BridgeBehaviorEndStateType, String>(2) {
          Obj!BridgeBehaviorEndStateType@1: "turn_off",
          Obj!BridgeBehaviorEndStateType@2: "nightlight"
        }
      POOL
      'behaviors/wake_up/behavior.yaml' => <<~YAML,
        script_id: ff8957e3-2eb9-4699-a0c8-ad2cb3ede704
        creation:
          - step_type: lights_selection
            result_name: where
          - step_type: time_and_recurrence_selection
            result_name: when
          - step_type: composite
            steps:
              - step_type: option_selection_step
                result_name: style
                options:
                  - value: sunrise
                    required_feature: style_sunrise
                  - value: basic
              - step_type: brightness_selection
                result_name: end_brightness
                required_feature: intensity
              - step_type: lights_off_after_selection
                result_name: turn_lights_off_after
          - step_type: fade_selection
            result_name: fade_in_duration
          - step_type: state_selection
          - step_type: name_setting
        editing:
          - step_type: name_setting
      YAML
      'behaviors/go_to_sleep/behavior.yaml' => <<~YAML,
        script_id: 7e571ac6-f363-42e1-809a-4cbf6523ed72
        creation:
          - step_type: end_state_selection
            result_name: end_state
        editing:
          - step_type: time_and_recurrence_selection
            result_name: when
            configuration:
              fade_selection_step:
                step_type: fade_selection
                result_name: fade_out_duration
      YAML
      'behaviors/pm_automation/behavior.yaml' => <<~YAML,
        script_id: db06cabc-c752-4904-9e8f-4ebe98feaa1a
        creation:
          - step_type: option_selection_step
            result_name: excluded_lights
        editing:
          - step_type: option_selection_step
            result_name: excluded_lights
            options:
              - value: turn_off
              - value: do_nothing
      YAML
      'behaviors/state_after_streaming/behavior.yaml' => <<~YAML
        script_id: 7719b841-6b3d-448d-a0e7-601ae9edb6a2
        creation:
          - step_type: streaming_end_scene_selection
            result_name: end_scene
        editing: []
      YAML
    )
  end

  after { FileUtils.remove_entry(directory) }

  def fields(name) = data.fetch('classes').fetch(name).fetch('fields')

  it 'names a script after its folder and gives its uuid' do
    expect(data['scripts']).to include(
      'ff8957e3-2eb9-4699-a0c8-ad2cb3ede704' => { 'name' => 'wake_up', 'configuration' => 'WakeUpConfiguration' },
      'db06cabc-c752-4904-9e8f-4ebe98feaa1a' => { 'name' => 'pm_automation',
                                                  'configuration' => 'PmAutomationConfiguration' }
    )
  end

  it 'gives a key per result_name, with the type of its step', :aggregate_failures do
    expect(fields('WakeUpConfiguration').keys).to contain_exactly(
      'where', 'when', 'style', 'end_brightness', 'turn_lights_off_after', 'fade_in_duration'
    )
    expect(fields('WakeUpConfiguration')['where']['type']).to eq('list' => { 'class' => 'BehaviorGroupAndLights' })
    expect(fields('WakeUpConfiguration')['fade_in_duration']['type']).to eq('class' => 'BehaviorFadeDuration')
    expect(fields('WakeUpConfiguration')['turn_lights_off_after']['type']).to eq('class' => 'TimeSpan')
  end

  it 'takes the values of an option step from its options' do
    expect(fields('WakeUpConfiguration')['style']).to include('type' => 'String', 'values' => %w[sunrise basic])
  end

  it 'takes the options of a step from its editing form when its creation form hides them' do
    expect(fields('PmAutomationConfiguration')['excluded_lights']).to include('values' => %w[turn_off do_nothing])
  end

  it 'takes the values of an end state from the enum of the app' do
    expect(fields('GoToSleepConfiguration')['end_state']).to include('type' => 'String',
                                                                     'values' => %w[
                                                                       turn_off nightlight
                                                                     ])
  end

  it 'finds the fade step an editing step nests in its configuration' do
    expect(fields('GoToSleepConfiguration')['fade_out_duration']['type']).to eq('class' => 'BehaviorFadeDuration')
  end

  it 'requires a creation step, unless a feature gates it or switching it off omits it' do
    required = fields('WakeUpConfiguration').select { |_, field| field['required'] }.keys
    expect(required).to contain_exactly('where', 'when', 'fade_in_duration')
  end

  it 'leaves the end scene optional, as only one end state uses it' do
    expect(fields('StateAfterStreamingConfiguration')['end_scene']['required']).to be(false)
  end

  it 'leaves a step of the editing form alone optional' do
    expect(fields('GoToSleepConfiguration')['when']['required']).to be(false)
  end

  it 'gives the native go to sleep the configuration of go to sleep' do
    expect(data['scripts']['a5624529-bd7e-4bc8-9d2f-9200476f106e'])
      .to eq('name' => 'native_go_to_sleep', 'configuration' => 'GoToSleepConfiguration')
  end

  it 'stops on a step type it does not know' do
    File.write(File.join(directory, 'behaviors/wake_up/behavior.yaml'),
               "script_id: x\ncreation:\n  - step_type: new_step\n    result_name: y\n")
    expect { data }.to raise_error(ArgumentError, /new_step/)
  end
end
