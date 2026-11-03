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

  it 'types a Tap Dial by its script', :aggregate_failures do
    value = configuration(:tap_switch, { 'button1' => { 'on_short_release' => { 'action' => 'dim_up' } } })
    expect(value).to be_a(schema::AccessoryBehaviorHTDSConfiguration)
    expect(value.button1.on_short_release.action).to eq('dim_up')
  end

  it 'types a motion sensor by its script' do
    expect(configuration(:motion_sensor, { 'source' => { 'rid' => 'x', 'rtype' => 'device' } }))
      .to be_a(schema::AccessoryBehaviorMotionSensorConfiguration)
  end

  it 'types a contact sensor by its script' do
    expect(configuration(:contact_sensor, { 'device' => { 'rid' => 'x', 'rtype' => 'device' } }))
      .to be_a(schema::AccessoryBehaviorContactSensorConfiguration)
  end

  it 'reads a scene cycle, a list of lists of actions, and round-trips it' do
    action = { 'scene_cycle' => [[{ 'action' => { 'recall' => scene } }], [{ 'action' => 'all_off' }]] }
    expect(round_trip(schema::AccessoryAction.from(action))).to eq(action)
  end
end
