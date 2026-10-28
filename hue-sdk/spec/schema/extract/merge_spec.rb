# frozen_string_literal: true

require_relative '../../../schema/extract/merge'

RSpec.describe Schema::Extract::Merge do
  subject(:merge) do
    described_class.new(responses:, requests:, aiohue: Schema::Extract::Aiohue.new(aiohue), capture:,
                        models: { 'light' => Hue::Sdk::Models::Light, 'bridge' => Hue::Sdk::Models::Bridge })
  end

  let(:responses) do
    { 'added' => {
      'LightAdded' => { 'id' => { 'type' => 'String' }, 'on' => { 'class' => 'OnFeatureAdded' },
                        'mode' => { 'type' => 'String?' }, 'effects' => { 'items' => 'String' },
                        'gradient' => { 'items' => 'GradientPointAdded' }, 'updated' => { 'type' => 'DateTime' } },
      'OnFeatureAdded' => { 'on' => { 'type' => 'bool' } },
      'GradientPointAdded' => { 'color' => { 'type' => 'String' } },
      'BridgeAdded' => { 'id' => { 'type' => 'String' }, 'bridge_id' => { 'type' => 'String' } }
    } }
  end
  let(:requests) do
    written = ->(offset, required, kind = 'pointer') { { 'offset' => offset, 'kind' => kind, 'required' => required } }
    { 'update' => {
      'LightUpdate' => { 'written' => { 'id' => written[4, true], 'on' => written[12, false],
                                        'mode' => written[16, true], 'duration' => written[20, false],
                                        'dimming' => written[24, false], 'signaling' => written[28, false] },
                         'declared' => { 24 => 'DimmingUpdate' } },
      'OnFeatureUpdate' => { 'written' => { 'on' => written[8, true] }, 'declared' => { 8 => 'bool' } },
      'DimmingUpdate' => { 'written' => { 'brightness' => written[8, true, 'double'],
                                          'step' => written[16, false, 'int'] }, 'declared' => {} },
      'SignalingFeatureUpdate' => { 'written' => { 'signal' => written[8, true], 'colors' => written[12, false] },
                                    'declared' => {} },
      'BridgeUpdate' => { 'written' => { 'identify' => written[8, true],
                                         'action' => { 'kind' => 'string', 'required' => true } }, 'declared' => {} }
    }, 'add' => {} }
  end
  let(:aiohue) do
    field = ->(name, type, default = nil) { { 'name' => name, 'type' => type, 'default' => default } }
    optional = ->(name, type) { field[name, "#{type} | None", 'None'] }
    classes = {
      'Light' => [field['id', 'str'], field['on', 'OnFeature'], field['mode', 'LightMode'],
                  field['type', 'ResourceTypes', 'ResourceTypes.LIGHT'], optional['effects', 'list[str]'],
                  field['gradient', 'list[GradientPoint]']],
      'OnFeature' => [field['on', 'bool']], 'GradientPoint' => [field['color', 'str']],
      'LightPut' => [optional['on', 'OnFeature'], optional['mode', 'LightMode'], optional['duration', 'int'],
                     optional['dimming', 'DimmingFeaturePut'], optional['signaling', 'SignalingFeaturePut']],
      'DimmingFeaturePut' => [field['brightness', 'float'], optional['step', 'int']],
      'SignalingFeaturePut' => [field['signal', 'SignalType'], optional['colors', 'list[str]']]
    }
    { 'classes' => classes.transform_values { { 'bases' => [], 'fields' => it } },
      'enums' => { 'LightMode' => { 'values' => %w[normal streaming] },
                   'SignalType' => { 'values' => %w[no_signal on_off] } } }
  end
  let(:capture) do
    [{ 'id' => 'l1', 'type' => 'light', 'on' => { 'on' => true }, 'mode' => 'normal', 'effects' => [],
       'gradient' => [{ 'color' => 'a' }, {}] },
     { 'id' => 'l2', 'type' => 'light', 'on' => { 'on' => false }, 'gradient' => [{ 'color' => 'b' }] },
     { 'id' => 'b1', 'type' => 'bridge', 'bridge_id' => 'x' }]
  end
  let(:schema) { merge.schema }

  def fields(name, attribute) = schema['classes'].dig(name, 'fields').transform_values { it[attribute] }

  it 'gives each resource type its response and request classes, named after the app classes', :aggregate_failures do
    expect(schema['resources']).to eq('bridge' => { 'response' => 'Bridge', 'update' => 'BridgeUpdate' },
                                      'light' => { 'response' => 'Light', 'update' => 'LightUpdate' })
    expect(schema['classes'].transform_values { it['origin'] }).to eq(
      'Bridge' => 'BridgeAdded', 'BridgeUpdate' => 'BridgeUpdate', 'DimmingUpdate' => 'DimmingUpdate',
      'GradientPoint' => 'GradientPointAdded', 'Light' => 'LightAdded', 'LightUpdate' => 'LightUpdate',
      'OnFeature' => 'OnFeatureAdded', 'OnFeatureUpdate' => 'OnFeatureUpdate',
      'SignalingFeatureUpdate' => 'SignalingFeatureUpdate'
    )
  end

  it 'types a response field from what fromJson decodes, and one it cannot type as an object' do
    expect(fields('Light', 'type')).to eq(
      'id' => 'String', 'on' => { 'class' => 'OnFeature' }, 'mode' => 'String', 'effects' => { 'list' => 'String' },
      'gradient' => { 'list' => { 'class' => 'GradientPoint' } }, 'updated' => 'Object'
    )
  end

  it 'types a request field from the class blutter gives it, its kind or its response counterpart' do
    expect([fields('LightUpdate', 'type').slice('on', 'mode', 'dimming'), fields('DimmingUpdate', 'type')])
      .to eq([{ 'on' => { 'class' => 'OnFeatureUpdate' }, 'mode' => 'String',
                'dimming' => { 'class' => 'DimmingUpdate' } }, { 'brightness' => 'Numeric', 'step' => 'Integer' }])
  end

  it 'types a write-only request field from aiohue, down to the fields of a class it names' do
    expect([fields('LightUpdate', 'type').slice('duration', 'signaling'), fields('SignalingFeatureUpdate', 'type'),
            fields('BridgeUpdate', 'type')['identify']])
      .to eq([{ 'duration' => 'Integer', 'signaling' => { 'class' => 'SignalingFeatureUpdate' } },
              { 'signal' => 'String', 'colors' => { 'list' => 'String' } }, 'Object'])
  end

  it 'types a request field the app writes with a constant from the constant' do
    expect(fields('BridgeUpdate', 'type')['action']).to eq('String')
  end

  it 'requires a response field aiohue requires and every captured resource holds, and the id of any resource' do
    expect([fields('Light', 'required'), fields('GradientPoint', 'required'), fields('Bridge', 'required')])
      .to eq([{ 'id' => true, 'on' => true, 'mode' => false, 'effects' => false, 'gradient' => true,
                'updated' => false }, { 'color' => false }, { 'id' => true, 'bridge_id' => false }])
  end

  it 'requires a request field the app always writes, unless aiohue lets it be None' do
    expect(%w[LightUpdate DimmingUpdate SignalingFeatureUpdate BridgeUpdate].map { fields(it, 'required') })
      .to eq([{ 'on' => false, 'mode' => false, 'duration' => false, 'dimming' => false, 'signaling' => false },
              { 'brightness' => true, 'step' => false }, { 'signal' => true, 'colors' => false },
              { 'identify' => true, 'action' => true }])
  end

  it 'takes the values of an enum from aiohue' do
    expect([fields('Light', 'values')['mode'], fields('LightUpdate', 'values')['mode'],
            fields('SignalingFeatureUpdate', 'values')['signal']])
      .to eq([%w[normal streaming], %w[normal streaming], %w[no_signal on_off]])
  end

  it 'reports each kind of finding on a line', :aggregate_failures do
    schema
    expect(merge.report.lines(chomp: true).map { it[/\A.+?\(\d+\)/] }).to eq(
      ['no aiohue class for response (1)', 'no aiohue class for update (1)', 'response field left untyped (1)',
       'request type inferred from the response class (1)', 'request type taken from aiohue (4)',
       'request field left untyped (1)', 'aiohue requires, live lacks (2)', 'app requires, aiohue does not (1)']
    )
    expect(merge.report).to include('response field left untyped (1): Light.updated')
  end
end
