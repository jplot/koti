# frozen_string_literal: true

RSpec.describe Hue::Sdk::Schema::BehaviorInstance, '.from' do
  let(:schema) { Hue::Sdk::Schema }
  let(:scene) { { 'rid' => '22222222-2222-4222-8222-222222222222', 'rtype' => 'scene' } }
  let(:button) { '33333333-3333-4333-8333-333333333333' }
  let(:where) { [{ 'group' => { 'rid' => '11111111-1111-4111-8111-111111111111', 'rtype' => 'room' } }] }

  def switch
    press = { 'recall_single_extended' => { 'actions' => [{ 'action' => { 'recall' => scene } }],
                                            'with_off' => { 'enabled' => true } } }
    { 'buttons' => { button => { 'on_long_press' => { 'action' => 'home_off' }, 'on_short_release' => press, where: } },
      'device' => { 'rid' => '44444444-4444-4444-8444-444444444444', 'rtype' => 'device' }, 'model_id' => 'RDM005' }
      .then { JSON.parse(JSON.generate(it)) }
  end

  def timeslot
    { 'on_motion' => { 'recall_single' => [{ 'action' => { 'recall' => scene } }] },
      'on_no_motion' => { 'after' => { 'minutes' => 10 }, 'recall_single' => [{ 'action' => 'all_off' }] },
      'start_time' => { 'time' => { 'hour' => 7, 'minute' => 0 }, 'type' => 'time' } }
  end

  def area
    offsets = { 'sunrise_offset' => { 'hours' => 0 }, 'sunset_offset' => { 'hours' => 0 } }
    service = { 'rid' => '66666666-6666-4666-8666-666666666666', 'rtype' => 'convenience_area_motion' }
    { 'source' => { 'rid' => '55555555-5555-4555-8555-555555555555', 'rtype' => 'motion_area_configuration' },
      'light_level' => { 'daylight' => { 'sunrise_sunset' => offsets } },
      'motion' => { 'motion_service' => service, 'when' => { 'timeslots' => [timeslot] }, 'where' => where } }
  end

  def configuration(name, data)
    id = schema::BEHAVIOR_SCRIPTS.fetch(name)
    described_class.from('script_id' => id, 'configuration' => data).configuration
  end

  def action_forms
    slot = { 'start_time' => { 'hour' => 7, 'minute' => 0 }, 'signal' => {},
             'actions' => [{ 'action' => { 'recall' => scene } }] }
    [{ 'time_based' => [slot] },
     { 'time_based_extended' => { 'slots' => [slot], 'repeat_timeout' => { 'seconds' => 2 } } },
     { 'scene_cycle_extended' => { 'slots' => [[{ 'action' => 'all_off' }]], 'with_off' => { 'enabled' => false } } },
     { 'behavior_trigger' => { 'behavior' => resource('behavior_instance'), 'trigger' => 'start' } },
     { 'sound_targets_control' => { 'action' => 'play', 'content_id' => 'x' } },
     { 'after' => { 'minutes' => 1 }, 'timer' => { 'duration' => { 'hours' => 1 }, 'type' => 'time_out_after' } }]
  end

  def resource(rtype) = { 'rid' => '77777777-7777-4777-8777-777777777777', 'rtype' => rtype }

  def round_trip(value) = JSON.parse(JSON.generate(value.to_body))

  it 'types a switch, and round-trips it', :aggregate_failures do
    value = configuration(:hue_accessories, switch)
    expect(value).to be_a(schema::AccessoryGenericConfiguration)
    expect(value.buttons.fetch(button).on_long_press.action).to eq('home_off')
    expect(value.buttons.fetch(button).on_short_release.recall_single_extended.with_off.enabled).to be(true)
    expect(round_trip(value)).to eq(switch)
  end

  it 'types a MotionAware area, which has no device nor model_id, and round-trips it', :aggregate_failures do
    value = configuration(:hue_accessories, area)
    expect(value.source.rtype).to eq('motion_area_configuration')
    expect(value.motion.when.timeslots.first.on_no_motion.after.minutes).to eq(10)
    expect(round_trip(value)).to eq(area)
  end

  it 'types a Tap Dial by its script, and round-trips it', :aggregate_failures do
    press = { 'on_short_release' => { 'action' => 'dim_up' } }
    data = { 'device' => resource('device'), 'button1' => press, 'button2' => press, 'button3' => press,
             'button4' => press, 'rotary' => { 'on_rotate' => { 'action' => 'dim_alternate' } } }
    value = configuration(:tap_switch, data)
    expect(value).to be_a(schema::AccessoryBehaviorHTDSConfiguration)
    expect(round_trip(value)).to eq(data)
  end

  it 'types what the motion sensor script holds, and round-trips it', :aggregate_failures do
    sensitivity = { 'daylight_sensitivity' => { 'dark_threshold' => 16_000, 'offset' => 7000 } }
    data = { 'source' => resource('camera_motion'), 'where' => where, 'settings' => sensitivity,
             'when' => { 'timeslots' => [timeslot] } }
    value = configuration(:motion_sensor, data)
    expect(value).to be_a(schema::AccessoryBehaviorMotionSensorConfiguration)
    expect(round_trip(value)).to eq(data)
  end

  it 'types a contact sensor by its script, and round-trips it', :aggregate_failures do
    on_close = { 'recall_single' => [{ 'action' => 'all_off' }],
                 'timer' => { 'duration' => { 'minutes' => 2 }, 'type' => 'after_a_set_time' } }
    actions = { 'on_open' => { 'recall_single' => [{ 'action' => { 'recall' => scene } }] }, 'on_close' => on_close }
    data = { 'device' => resource('device'), 'where' => where, 'when' => { 'always' => actions } }
    value = configuration(:contact_sensor, data)
    expect(value).to be_a(schema::AccessoryBehaviorContactSensorConfiguration)
    expect(round_trip(value)).to eq(data)
  end

  it 'round-trips every other form of action of a button' do
    expect(action_forms.map { round_trip(schema::AccessoryAction.from(it)) }).to eq(action_forms)
  end

  it 'keeps a table of rotaries' do
    data = { 'rotaries' => { button => { 'on_rotate' => { 'action' => 'dim_up' } } } }
    expect(configuration(:hue_accessories, data).rotaries.fetch(button).on_rotate.action).to eq('dim_up')
  end

  it 'keeps as they are the forms it cannot decode, as the app does', :aggregate_failures do
    [{ 'recall_single' => { 'action' => 'all_off' } }, { 'recall_single_extended' => [] },
     { 'recall_single_extended' => 'x' }, { 'behavior_trigger' => 'x' }].each do |form|
      data = { 'buttons' => { button => { 'on_short_release' => form } } }
      expect(configuration(:hue_accessories, data)).to eq(data)
    end
  end

  it 'reads a scene cycle, a list of lists of actions, and round-trips it' do
    action = { 'scene_cycle' => [[{ 'action' => { 'recall' => scene } }], [{ 'action' => 'all_off' }]] }
    expect(round_trip(schema::AccessoryAction.from(action))).to eq(action)
  end
end
