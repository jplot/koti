# frozen_string_literal: true

RSpec.describe Hue::Sdk::Events::Stream do
  subject(:stream) { described_class.new(sleeper: method(:record_delay)) }

  let(:delays) { [] }
  let(:message) { light_update_message }
  let(:bridge) { FakeBridge.start { |request| answer(request) } }

  before { connect_to(bridge) }

  after { bridge.stop }

  def answer(_request) = [200, { 'Content-Type' => 'text/event-stream' }, message]

  def record_delay(seconds)
    delays << seconds
    throw :stop if delays.size == 7
  end

  def take_events(count, &read)
    read ||= :itself.to_proc
    found = []
    catch(:enough) do
      stream.each do |event|
        found << read.call(event)
        throw :enough if found.size == count
      end
    end
    found
  end

  it 'asks for the event stream with the application key' do
    take_events(1)
    expect(bridge.requests.first).to have_attributes(
      verb: 'GET', path: '/eventstream/clip/v2',
      headers: include('accept' => 'text/event-stream', 'hue-application-key' => 'test-key')
    )
  end

  it 'reconnects with the last event id', :aggregate_failures do
    take_events(3)
    expect(bridge.requests.map { it.headers['last-event-id'] }).to eq([nil, '1:0'])
    expect(delays).to eq([1])
  end

  it 'waits 1, 2, 4, 8, 16 then 30 seconds while the bridge is unreachable' do
    bridge.down!
    catch(:stop) { stream.each { nil } }
    expect(delays).to eq([1, 2, 4, 8, 16, 30, 30])
  end

  it 'waits 1 second again once a message arrives' do
    catch(:stop) { stream.each { nil } }
    expect(delays).to eq([1] * 7)
  end

  it 'fails at once when the host is not configured', :aggregate_failures do
    Hue::Sdk.config.host = nil
    expect { stream.each { nil } }.to raise_error(Hue::Sdk::ConnectionError, /host is not configured/)
    expect(delays).to be_empty
  end

  it 'requires an application key', :aggregate_failures do
    Hue::Sdk.config.application_key = nil
    expect { stream.each { nil } }.to raise_error(Hue::Sdk::AuthenticationError, /not configured/)
    expect(bridge.requests).to be_empty
  end

  context 'when the bridge rejects the application key' do
    def answer(_request) = [403, { 'Content-Type' => 'application/json' }, '{"errors":[],"data":[]}']

    it 'raises AuthenticationError without reconnecting', :aggregate_failures do
      expect { stream.each { nil } }.to raise_error(Hue::Sdk::AuthenticationError)
      expect(bridge.requests.size).to eq(1)
    end
  end

  context 'when the bridge answers another error status' do
    def answer(_request) = [503, { 'Content-Type' => 'application/json' }, '{"errors":[],"data":[]}']

    it 'raises ResponseError without reconnecting' do
      expect { stream.each { nil } }
        .to raise_error(an_instance_of(Hue::Sdk::ResponseError).and(having_attributes(status: 503)))
    end
  end

  context 'when the block reads the bridge while a long message is still arriving' do
    let(:message) { "#{super()}: #{'x' * 40_000}\n\n" }

    def answer(request)
      return super unless request.path.start_with?('/clip/v2/')

      [200, { 'Content-Type' => 'application/json' }, JSON.generate(data: [{ id: 'l1', on: { on: true } }], errors: [])]
    end

    it 'serves the read on another connection' do
      expect(take_events(1) { it.resource['on'] }).to eq([{ 'on' => true }])
    end
  end
end
