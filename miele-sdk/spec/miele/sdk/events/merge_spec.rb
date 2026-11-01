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

  def counting(produced)
    Object.new.tap do |source|
      source.define_singleton_method(:each) do |&block|
        3.times do |number|
          block.call(number)
          produced << number
        end
        sleep
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
    threads = Thread.list
    merge.each.first
    expect([closed.pop, closed.pop]).to contain_exactly(:local, :cloud)
    expect(Thread.list - threads).to be_empty
  end

  it 'reads a single source on a thread of its own, so that a slow block does not hold it back' do
    produced = Queue.new
    seen = nil
    described_class.new([counting(produced)]).each do |number|
      seen = Array.new(3) { produced.pop }
      break if number.zero?
    end
    expect(seen).to eq([0, 1, 2])
  end

  def failing_cleanup
    Object.new.tap do |source|
      source.define_singleton_method(:each) do |&block|
        loop { block.call(:event) && sleep(0.01) }
      ensure
        raise Miele::Sdk::ResponseError, 500
      end
    end
  end

  it 'raises what a source raises as it cleans up after the block breaks' do
    expect { described_class.new([failing_cleanup]).each.first }.to raise_error(Miele::Sdk::ResponseError)
  end

  it 'leaves the error of the block to the caller over a failed cleanup' do
    stop = ->(_event) { raise 'stop' }
    expect { described_class.new([failing_cleanup]).each(&stop) }.to raise_error(RuntimeError, 'stop')
  end

  it 'leaves a failed cleanup to the caller even within a rescue of the caller' do
    expect do
      raise ArgumentError
    rescue ArgumentError
      described_class.new([failing_cleanup]).each.first
    end.to raise_error(Miele::Sdk::ResponseError)
  end

  it 'raises in the calling thread what a source raises' do
    failing = Class.new { def each = raise(Miele::Sdk::ConnectionError, 'gone') }.new
    expect { described_class.new([failing, source(:local)]).each { nil } }
      .to raise_error(Miele::Sdk::ConnectionError, 'gone')
  end
end
