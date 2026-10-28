# frozen_string_literal: true

RSpec.describe Hue::Sdk::Events do
  let(:bridge) { FakeBridge.start { [200, { 'Content-Type' => 'text/event-stream' }, light_update_message] } }

  before { connect_to(bridge) }

  after { bridge.stop }

  it 'yields one event per resource of a message', :aggregate_failures do
    events = []
    Hue::Sdk.events { |event| break if (events << event).size == 2 }
    expect(events.map(&:resource_id)).to eq(%w[l1 l2])
    expect(events.first).to have_attributes(id: 'c1', kind: :update, created_at: Time.utc(2026, 10, 25, 10),
                                            resource_type: 'light', changes: { 'on' => { 'on' => true } })
  end

  it 'returns a lazy enumerator without a block', :aggregate_failures do
    events = Hue::Sdk.events
    expect(events).to be_a(Enumerator::Lazy)
    expect(events.first(1).map(&:resource_id)).to eq(['l1'])
  end

  it 'resolves the resource of an event' do
    expect(Hue::Sdk.events.first.resource).to be_a(Hue::Sdk::Models::Light::Instance).and(have_attributes(id: 'l1'))
  end

  context 'when a change concerns a type this version does not know' do
    let(:bridge) do
      change = { id: 'f1', type: 'future', level: 3 }
      container = { creationtime: '2026-10-25T10:00:00Z', id: 'c1', type: 'update', data: [change] }
      message = "id: 1:0\ndata: #{JSON.generate([container])}\n\n"
      FakeBridge.start { [200, { 'Content-Type' => 'text/event-stream' }, message] }
    end

    it 'yields it with a generic resource', :aggregate_failures do
      event = Hue::Sdk.events.first
      expect(event).to have_attributes(resource_type: 'future', changes: { 'level' => 3 })
      expect(event.resource).to be_a(Hue::Sdk::Models::Resource::Instance)
    end
  end

  context 'when a change carries a deprecated field' do
    let(:bridge) do
      message = light_update_message(effects: { status: 'no' })
      FakeBridge.start { [200, { 'Content-Type' => 'text/event-stream' }, message] }
    end

    it 'leaves it out of the changes' do
      expect(Hue::Sdk.events.first.changes).to eq('on' => { 'on' => true })
    end
  end
end
