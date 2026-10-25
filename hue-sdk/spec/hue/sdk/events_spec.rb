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
end
