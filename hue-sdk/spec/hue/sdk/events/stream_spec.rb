# frozen_string_literal: true

RSpec.describe Hue::Sdk::Events::Stream do
  subject(:stream) { described_class.new }

  let(:message) { light_update_message }
  let(:bridge) { FakeBridge.start { |request| answer(request) } }

  before { connect_to(bridge) }

  after { bridge.stop }

  def answer(_request) = [200, { 'Content-Type' => 'text/event-stream' }, message]

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

  it 'reads the stream once, to its end, keeping the id of its last message to resume from', :aggregate_failures do
    expect(take_events(3).map(&:resource_id)).to eq(%w[l1 l2])
    expect([bridge.requests.size, stream.last_event_id]).to eq([1, '1:0'])
  end

  it 'resumes from the id it is given' do
    described_class.new(last_event_id: '1:0').each { nil }
    expect(bridge.requests.first.headers['last-event-id']).to eq('1:0')
  end

  it 'raises ConnectionError when the bridge cannot be reached, reconnecting nothing' do
    bridge.down!
    expect { stream.each { nil } }.to raise_error(Hue::Sdk::ConnectionError)
  end

  it 'keeps the id of the last message whose events the block took whole', :aggregate_failures do
    resumed = described_class.new(last_event_id: '0:9')
    expect { resumed.each { raise 'stop' if it.resource_id == 'l2' } }.to raise_error('stop')
    expect(resumed.last_event_id).to eq('0:9')
  end

  it 'lets an error raised by the block reach the caller', :aggregate_failures do
    expect { stream.each { File.read('/nonexistent') } }.to raise_error(Errno::ENOENT)
    expect(bridge.requests.size).to eq(1)
  end

  it 'fails at once when the host is not configured' do
    Hue::Sdk.config.host = nil
    expect { stream.each { nil } }.to raise_error(Hue::Sdk::ConnectionError, /host is not configured/)
  end

  it 'requires an application key', :aggregate_failures do
    Hue::Sdk.config.application_key = nil
    expect { stream.each { nil } }.to raise_error(Hue::Sdk::AuthenticationError, /not configured/)
    expect(bridge.requests).to be_empty
  end

  context 'when the bridge drops the stream without closing TLS' do
    def answer(_request) = [200, { 'Content-Type' => 'text/event-stream' }, message, :cut]

    it 'raises ConnectionError after the events it read, their id kept', :aggregate_failures do
      found = []
      expect { stream.each { found << it.resource_id } }.to raise_error(Hue::Sdk::ConnectionError)
      expect([found, stream.last_event_id]).to eq([%w[l1 l2], '1:0'])
    end
  end

  context 'when the bridge drops the connection before it answers' do
    def answer(_request) = :drop

    it 'raises ConnectionError without sending the request again', :aggregate_failures do
      expect { stream.each { nil } }.to raise_error(Hue::Sdk::ConnectionError)
      expect(bridge.requests.size).to eq(1)
    end
  end

  context 'when the bridge rejects the application key' do
    def answer(_request) = [403, { 'Content-Type' => 'application/json' }, '{"errors":[],"data":[]}']

    it 'raises AuthenticationError', :aggregate_failures do
      expect { stream.each { nil } }.to raise_error(Hue::Sdk::AuthenticationError)
      expect(bridge.requests.size).to eq(1)
    end
  end

  context 'when the bridge answers another error status' do
    def answer(_request) = [503, { 'Content-Type' => 'application/json' }, '{"errors":[],"data":[]}']

    it 'raises ResponseError' do
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
