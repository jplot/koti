# frozen_string_literal: true

RSpec.describe Hue::Sdk::Schema::BehaviorInstance do
  let(:schema) { Hue::Sdk::Schema }
  let(:go_to_sleep) do
    { 'end_state' => 'turn_off', 'fade_out_duration' => { 'seconds' => 1800 }, 'style' => 'basic',
      'when' => { 'recurrence_days' => ['monday'], 'time_point' => { 'time' => { 'hour' => 22, 'minute' => 30 },
                                                                     'type' => 'time' } },
      'where' => [{ 'group' => { 'rid' => '11111111-1111-4111-8111-111111111111', 'rtype' => 'room' },
                    'items' => [{ 'rid' => '22222222-2222-4222-8222-222222222222', 'rtype' => 'light' }] }] }
  end

  def instance(script_id, configuration, state: nil)
    described_class.from('script_id' => script_id, 'configuration' => configuration, 'state' => state)
  end

  def script(name) = schema::BEHAVIOR_SCRIPTS.fetch(name)

  it 'reads the configuration with the class of its script', :aggregate_failures do
    configuration = instance(script(:go_to_sleep), go_to_sleep).configuration
    expect(configuration).to be_a(schema::GoToSleepConfiguration)
    expect(configuration.when.time_point.time.hour).to eq(22)
    expect(configuration.where.first.items.first.rtype).to eq('light')
  end

  it 'round-trips a real configuration to the same JSON' do
    configuration = instance(script(:go_to_sleep), go_to_sleep).configuration
    expect(JSON.parse(JSON.generate(configuration.to_body))).to eq(go_to_sleep)
  end

  it 'keeps a key its class does not know, and sends it back', :aggregate_failures do
    configuration = instance(script(:go_to_sleep), go_to_sleep.merge('new_key' => { 'a' => 1 })).configuration
    expect(configuration.unknown).to eq('new_key' => { 'a' => 1 })
    expect(JSON.parse(JSON.generate(configuration.to_body))).to eq(go_to_sleep.merge('new_key' => { 'a' => 1 }))
  end

  it 'sends a configuration that lacks a key the app defaults' do
    where = [{ 'group' => { 'rid' => '11111111-1111-4111-8111-111111111111', 'rtype' => 'room' } }]
    configuration = instance(script(:pm_automation), { 'where' => where, 'mode' => '24h' }).configuration
    expect(JSON.parse(JSON.generate(configuration.to_body))).to eq('where' => where, 'mode' => '24h')
  end

  it 'writes the lights of each scene from the lights of its group, as the app does' do
    group = { rid: '11111111-1111-4111-8111-111111111111', rtype: 'room' }
    lights = [schema::BehaviorLight.new(rid: '22222222-2222-4222-8222-222222222222', rtype: 'light')]
    typed = schema::TimerConfiguration.new(
      where: [schema::BehaviorGroupAndLights.new(group: schema::BehaviorGroup.new(**group), items: lights)],
      what: [schema::BehaviorGroupScene.new(group: schema::BehaviorGroup.new(**group))],
      duration: schema::TimeSpan.new(minutes: 5)
    )
    expect(typed.to_body[:what]).to eq([{ group:, items: [{ rid: lights.first.rid, rtype: 'light' }] }])
  end

  it 'reads the native go to sleep like go to sleep' do
    expect(instance(script(:native_go_to_sleep), go_to_sleep).configuration).to be_a(schema::GoToSleepConfiguration)
  end

  it 'keeps the hash of a script it does not know' do
    expect(instance('99999999-9999-4999-8999-999999999999', { 'x' => 1 }).configuration).to eq('x' => 1)
  end

  it 'leaves a configuration the bridge left out nil' do
    expect(instance(script(:timer), nil).configuration).to be_nil
  end

  it 'types the state' do
    state = instance(script(:timer), {}, state: { 'timer_state' => 'started' }).state
    expect(state.timer_state).to eq('started')
  end

  it 'keeps as a hash a configuration it would not send back whole, such as one missing a required key' do
    expect(instance(script(:wake_up), {}).configuration).to eq({})
  end

  it 'refuses an unknown field before sending' do
    expect { schema::WakeUpConfiguration.new(where: [], when: nil, fade_in_duration: nil, nope: 1) }
      .to raise_error(ArgumentError, /nope/)
  end

  it 'refuses a required field left out, or left nil, before sending', :aggregate_failures do
    expect { schema::WakeUpConfiguration.new(style: 'basic') }.to raise_error(ArgumentError, /where/)
    expect { schema::WakeUpConfiguration.new(where: nil, when: nil, fade_in_duration: nil).to_body }
      .to raise_error(ArgumentError, /where/)
  end

  it 'names every automation script' do
    expect(schema::BEHAVIOR_SCRIPTS.keys).to contain_exactly(
      :coming_home, :go_to_sleep, :leaving_home, :native_go_to_sleep, :pm_automation, :smoke_alarm,
      :state_after_streaming, :time_based, :timer, :wake_up, :hue_accessories, :tap_switch, :motion_sensor,
      :contact_sensor
    )
  end
end
