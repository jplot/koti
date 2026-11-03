# frozen_string_literal: true

RSpec.describe Hue::Sdk::Models::BehaviorInstance do
  let(:schema) { Hue::Sdk::Schema }
  let(:id) { '11111111-1111-4111-8111-111111111111' }
  let(:timer) { schema::BEHAVIOR_SCRIPTS.fetch(:timer) }
  let(:configuration) do
    { 'duration' => { 'minutes' => 5 }, 'what' => [], 'where' => [] }
  end
  let(:bridge) do
    FakeBridge.serving(
      "GET /clip/v2/resource/behavior_instance/#{id}" => {
        errors: [], data: [{ id:, type: 'behavior_instance', script_id: timer, enabled: true, configuration:,
                             state: { timer_state: 'paused' }, dependees: [], status: 'running', last_error: '',
                             metadata: { name: 'Pasta' } }]
      },
      'POST /clip/v2/resource/behavior_instance' => { errors: [], data: [{ rid: id, rtype: 'behavior_instance' }] },
      "PUT /clip/v2/resource/behavior_instance/#{id}" => { errors: [], data: [{ rid: id, rtype: 'behavior_instance' }] }
    )
  end

  before { connect_to(bridge) }

  after { bridge.stop }

  def sent = JSON.parse(bridge.requests.last.body)

  it 'reads an automation as typed values', :aggregate_failures do
    attributes = Hue::Sdk.BehaviorInstance(id).attributes
    expect(attributes.configuration.duration.minutes).to eq(5)
    expect(attributes.state.timer_state).to eq('paused')
  end

  it 'creates an automation from a typed request' do
    typed = schema::TimerConfiguration.new(where: [], what: [], duration: schema::TimeSpan.new(minutes: 5))
    metadata = schema::BehaviorMetadata.new(name: 'Pasta')
    request = schema::BehaviorInstanceAdd.new(script_id: timer, enabled: true, configuration: typed, metadata:)
    Hue::Sdk.BehaviorInstance.create(request)
    expect(sent).to eq('type' => 'behavior_instance', 'script_id' => timer, 'enabled' => true,
                       'configuration' => configuration,
                       'metadata' => { 'type' => 'instance_metadata', 'name' => 'Pasta' })
  end

  it 'sends only the fields a typed update gives' do
    Hue::Sdk.BehaviorInstance(id).update(schema::BehaviorInstanceUpdate.new(enabled: false))
    expect(sent).to eq('enabled' => false)
  end

  it 'triggers an automation as the app does' do
    trigger = schema::BehaviorTrigger.new(start: {})
    Hue::Sdk.BehaviorInstance(id).update(schema::BehaviorInstanceUpdate.new(trigger:))
    expect(sent).to eq('trigger' => { 'start' => {} })
  end

  it 'refuses a request whose configuration lacks a required field before sending', :aggregate_failures do
    typed = schema::TimerConfiguration.new(where: nil, what: [], duration: nil)
    metadata = schema::BehaviorMetadata.new(name: 'Pasta')
    request = schema::BehaviorInstanceAdd.new(script_id: timer, enabled: true, configuration: typed, metadata:)
    expect { Hue::Sdk.BehaviorInstance.create(request) }.to raise_error(ArgumentError, /where/)
    expect(bridge.requests).to be_empty
  end
end
