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
    it 'reads seconds or an HTTP date, as the app does', :aggregate_failures do
      expect(described_class.retry_after('5')).to eq(5)
      expect(described_class.retry_after((Time.now + 60).httpdate)).to be_between(58, 60)
      expect(described_class.retry_after('Wed, 21 Oct 2015 07:28:00 GMT')).to eq(0)
    end

    it 'gives nil for anything else', :aggregate_failures do
      [nil, 'soon', '-1'].each { expect(described_class.retry_after(it)).to be_nil }
    end
  end
end
