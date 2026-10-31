# frozen_string_literal: true

RSpec.describe Miele::Sdk::Events::Merge do
  subject(:merge) { described_class.new([source(:local), source(:cloud)]) }

  let(:closed) { Queue.new }

  around { |example| Timeout.timeout(5) { example.run } }

  # A source pushing its own event every 10 ms from the thread that runs it, as Listener and CloudStream do.
  def source(name)
    finished = closed
    Object.new.tap do |source|
      source.define_singleton_method(:each) do |&block|
        loop { block.call([name, Thread.current]) && sleep(0.01) }
      ensure
        finished << name
      end
    end
  end

  it 'merges local and cloud events on the calling thread', :aggregate_failures do
    received = []
    merge.each do |event|
      received << [event.first, Thread.current]
      break if received.map(&:first).uniq.size == 2
    end
    expect(received.map(&:first).uniq).to contain_exactly(:local, :cloud)
    expect(received.map(&:last).uniq).to eq([Thread.current])
  end

  it 'stops both sources, their cleanup run, when the block breaks', :aggregate_failures do
    threads = Thread.list.size
    merge.each.first
    expect([closed.pop, closed.pop]).to contain_exactly(:local, :cloud)
    expect(Thread.list.size).to eq(threads)
  end

  it 'raises in the calling thread what a source raises' do
    failing = Class.new { def each = raise(Miele::Sdk::ConnectionError, 'gone') }.new
    expect { described_class.new([failing, source(:local)]).each { nil } }
      .to raise_error(Miele::Sdk::ConnectionError, 'gone')
  end
end
