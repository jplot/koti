# frozen_string_literal: true

require 'uri'

RSpec.describe Miele::Sdk::Events::Listener do
  subject(:listener) { described_class.new(hosts: ['127.0.0.1'], mdns_address: '127.0.0.1', mdns_port: 0) }

  let(:fab) { '000123456789' }
  let(:subscriptions) { { '1' => cloud } }
  let(:callbacks) { Queue.new }
  let(:refusals) { {} }
  let(:fake) do
    store = subscriptions
    sent = callbacks
    refused = refusals
    FakeAppliance.start do |request|
      next refused[request.verb] if refused.key?(request.verb)

      slot = request.path[%r{\A/Subscriptions/(\d+)/\z}, 1]
      case [request.verb, slot]
      in ['GET', nil] if request.path == '/Devices/' then [200, {}, JSON.generate(fab => { 'href' => "#{fab}/" })]
      in ['GET', nil] then [200, {}, JSON.generate(store.keys.to_h { [it, { 'href' => "#{it}/" }] })]
      in ['GET', String] then [200, {}, JSON.generate(store.fetch(slot))]
      in ['DELETE', String] then [204, {}, ''].tap { store.delete(slot) }
      in ['POST', nil]
        store[(store.keys.map(&:to_i).max.to_i + 1).to_s] = JSON.parse(request.body).tap { sent << it['Callback'] }
        [201, {}, '']
      else [200, {}, '']
      end
    end
  end

  before do
    connect_to(fake)
    Miele::Sdk.config.listener_port = 0
  end

  after { fake.stop }

  def push_state
    Thread.new do
      callback = URI(Array.new(4) { callbacks.pop }.find { it.end_with?('/State/') })
      deliver(callback.port, 'POST', callback.path, JSON.generate(Resource: '/State/', Content: { Light: 1 }))
    end
  end

  def cloud = { 'Resource' => "/Devices/#{fab}/DOP2/1/1585/", 'Callback' => 'Cloud' }

  def supervision_puts = fake.requests.select { it.verb == 'PUT' }.map { JSON.parse(it.body) }

  it 'enrolls an appliance and yields its pushed events', :aggregate_failures do
    pusher = push_state
    event = Miele::Sdk::Events::Event.new(fab:, resource: '/State/', content: { 'Light' => 1 })
    expect(listener.each.first).to eq(event)
    expect(subscriptions.size).to eq(1)
    pusher.join
  end

  it 'subscribes to each pushed resource with a callback to this host' do
    push_state.tap { listener.each.first }.join
    callbacks = fake.requests.select { it.verb == 'POST' }.map { JSON.parse(it.body).fetch('Callback') }
    expect(callbacks.map { it[%r{/Devices/000999\d{6}/SuperVision/#{fab}(/.*)}, 1] })
      .to eq(%w[/State/ /State/Light/ /State/Status/ /Ident/])
  end

  it 'withdraws its subscriptions when the block ends', :aggregate_failures do
    push_state.tap { listener.each.first }.join
    expect(subscriptions).to eq('1' => cloud)
    expect(supervision_puts).to eq([{ 'Show' => true, 'Signal' => true }, { 'Show' => false, 'Signal' => false }])
  end

  it 'withdraws even when the block raises', :aggregate_failures do
    pusher = push_state
    stop = ->(_event) { raise 'stop' }
    expect { listener.each(&stop) }.to raise_error(RuntimeError, 'stop')
    expect(subscriptions).to eq('1' => cloud)
    pusher.join
  end

  it 'refuses an empty list of appliances' do
    expect { described_class.new(hosts: []) }.to raise_error(ArgumentError, /no appliance/)
  end

  it 'keeps streaming when an appliance cannot be enrolled', :aggregate_failures do
    pusher = push_state
    both = described_class.new(hosts: ['127.0.0.1', '::1'], mdns_address: '127.0.0.1', mdns_port: 0)
    expect { expect(both.each.first.fab).to eq(fab) }.to output(/no events from ::1/).to_stderr
    pusher.join
  end

  it 'returns a lazy enumerator without a block' do
    expect([listener.each, Miele::Sdk.events(hosts: ['127.0.0.1'])]).to all(be_a(Enumerator::Lazy))
  end

  context 'with an appliance without SuperVision' do
    let(:refusals) { { 'PUT' => [404, {}, ''] } }

    it 'still subscribes it' do
      pusher = push_state
      expect(listener.each.first.fab).to eq(fab)
      pusher.join
    end
  end

  context 'when an appliance refuses the withdrawal' do
    let(:refusals) { { 'DELETE' => [500, {}, ''] } }

    it 'warns that subscriptions stay on it' do
      pusher = push_state
      expect { listener.each.first }.to output(/subscriptions left on 127\.0\.0\.1: appliance answered 500/).to_stderr
      pusher.join
    end
  end
end
