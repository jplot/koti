# frozen_string_literal: true

RSpec.describe Miele::Sdk::Appliance do
  subject(:appliance) do
    described_class.new('127.0.0.1', fab:, ident:, sleeper: ->(_seconds) {}, clock: -> { 0.0 })
  end

  let(:fab) { '000123456789' }
  let(:ident) { Miele::Sdk::Schema::DeviceIdentification.from('DeviceType' => 1, 'ProtocolVersion' => 4) }
  let(:gates) { { renaming: Thread::Queue.new, read: Thread::Queue.new, ended: Thread::Queue.new } }
  let(:fake) do
    salon = 0
    FakeAppliance.start(threaded: true) do |request|
      case request
      in { verb: 'GET' }
        gates[:read] << 1
        [200, {}, '{"Status":1}']
      in { body: /Cuisine/ }
        gates[:renaming] << 1
        gates[:read].pop(timeout: 5)
        [204, {}, '']
      in { body: /Salon/ } if (salon += 1) == 1
        gates[:renaming] << 1
        gates[:ended].pop(timeout: 5)
        [503, {}, '']
      else [204, {}, '']
      end
    end
  end
  let(:sent) { Thread::Queue.new }

  before do
    connect_to(fake)
    Miele::Sdk.config.read_timeout = 30
    log = sent
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, *args, **options, &block|
      log << [Thread.current.name, options[:read_timeout]]
      start.call(*args, **options, &block)
    end
  end

  after { fake.stop }

  def on_thread(name)
    Thread.new do
      Thread.current.name = name
      Thread.current.report_on_exception = false
      yield
    end
  end

  def timeouts = Array.new(sent.size) { sent.pop }.group_by(&:first).transform_values { it.map(&:last) }

  it 'leaves a read on another thread its own timeout while an action runs' do
    action = on_thread('action') { appliance.name = 'Cuisine' }
    reader = on_thread('reader') { gates[:renaming].pop(timeout: 5) && appliance.state }
    [action, reader].each(&:join)
    expect(timeouts).to eq('action' => [15], 'reader' => [30])
  end

  it 'keeps an action its window when another action on the same appliance ends' do
    first = on_thread('first') { appliance.name = 'Salon' }
    second = on_thread('second') do
      gates[:renaming].pop(timeout: 5)
      appliance.name = 'Entrée'
      gates[:ended] << 1
    end
    [first, second].each(&:join)
    expect(timeouts).to eq('first' => [15, 15], 'second' => [15])
  end

  it 'gives a request sent once an action has ended its own timeout' do
    on_thread('caller') { (appliance.name = 'Entrée') && appliance.state }.join
    expect(timeouts).to eq('caller' => [15, 30])
  end
end
