# frozen_string_literal: true

RSpec.describe Hue::Sdk::RateLimiter do
  describe '.delay' do
    def delay(failures, retry_after, elapsed, draw = 1.0)
      described_class.delay(failures:, retry_after:, elapsed:, draw:)
    end

    it 'waits what Retry-After asks, less the time since the refusal, at most 30 s', :aggregate_failures do
      expect(delay(1, 10, 3)).to eq(7)
      expect(delay(1, 120, 0)).to eq(30)
      expect(delay(1, 1, 5)).to eq(0)
    end

    it 'backs off 2 s times 2^n − 1 times a draw without Retry-After, n at most 4', :aggregate_failures do
      expect(delay(1, nil, 0, 0.5)).to eq(1.0)
      expect(delay(3, nil, 0)).to eq(14.0)
      expect(delay(9, nil, 0)).to eq(30.0)
      expect(delay(2, nil, 10)).to eq(0)
    end
  end

  describe '.retry_after' do
    it "reads seconds as Dart's int.tryParse, or an HTTP date, as the app does", :aggregate_failures do
      { '5' => 5, '+5' => 5, '-0' => 0, 'Wed, 21 Oct 2015 07:28:00 GMT' => 0 }.each do |header, seconds|
        expect(described_class.retry_after(header)).to eq(seconds)
      end
      expect(described_class.retry_after((Time.now + 60).httpdate)).to be_between(58, 60)
    end

    it 'gives nil for anything else, a number past 64 bits included', :aggregate_failures do
      [nil, 'soon', '-1', '99999999999999999999'].each { expect(described_class.retry_after(it)).to be_nil }
    end
  end

  describe '#through' do
    let(:limiter) { described_class.new }
    let(:pauses) { [] }
    let(:answer_class) { Data.define(:code, :retry_after) { def [](_name) = retry_after } }

    before do
      allow(limiter).to receive(:sleep) { |seconds| pauses << seconds.round(1) }
      allow(limiter).to receive(:rand).and_return(0.5)
    end

    def answer(code, retry_after = nil) = limiter.through('host/a') { answer_class.new(code:, retry_after:) }

    it 'counts the 429s in a row, and starts again after any other answer' do
      %w[429 429 200 429 200].each { answer(it) }
      expect(pauses).to eq([1.0, 3.0, 1.0])
    end

    it 'starts again after a failure of any kind', :aggregate_failures do
      answer('429')
      expect { limiter.through('host/a') { raise Net::HTTPBadResponse, 'bad' } }.to raise_error(Net::HTTPBadResponse)
      %w[429 200].each { answer(it) }
      expect(pauses).to eq([1.0, 1.0])
    end

    it 'waits what Retry-After asked, less the time since the 429' do
      answer('429', '10')
      sleep 0.2
      answer('200')
      expect(pauses.first).to be_between(9.7, 9.85)
    end
  end
end
