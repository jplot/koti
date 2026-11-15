# frozen_string_literal: true

require 'time'

module Hue
  module Sdk
    # The app's BridgeRateLimiter, one per bridge connection: after a 429 it delays the next request to the same host
    # and path, whatever the method, and never sends the refused one again. Any other outcome, a failure included,
    # clears that delay.
    class RateLimiter
      BASE = 2.0
      CAP = 30.0
      MAX_FAILURES = 4
      private_constant :BASE, :CAP, :MAX_FAILURES

      # @api private
      def initialize
        @lock = Mutex.new
        @state = {}
      end

      # The app's wait: Retry-After less the time since the refusal, at most 30 s; without it, a full random draw
      # over 2 s × (2^n − 1) for n consecutive 429s, n at most 4 (expBackOffDelay).
      #
      # @param failures [Integer] consecutive 429s
      # @param retry_after [Float, nil] seconds the bridge asked
      # @param elapsed [Float] seconds since the 429
      # @param draw [Float] uniform in [0, 1)
      # @return [Float] seconds, never negative
      # @api private
      def self.delay(failures:, retry_after:, elapsed:, draw:)
        pause = if retry_after
                  [retry_after - elapsed, CAP].min
                else
                  (BASE * ((1 << [failures, MAX_FAILURES].min) - 1) * draw) - elapsed
                end
        [pause, 0.0].max
      end

      # The app reads seconds with Dart's int.tryParse, which takes a sign and 64 bits, and keeps them from 0 up;
      # else an HTTP date.
      #
      # @param header [String, nil] a Retry-After value
      # @return [Float, nil] seconds, or an HTTP date less now floored at 0
      # @api private
      def self.retry_after(header)
        return if header.nil?

        seconds = Integer(header, 10) if header.match?(/\A[+-]?\d+\z/)
        return seconds.to_f if seconds && seconds >= 0 && seconds < 2**63

        [Time.httpdate(header) - Time.now, 0.0].max
      rescue ArgumentError
        nil
      end

      # Waits what the app waits before a request to +key+, sends it, and keeps the outcome.
      #
      # @param key [String] host and path, without the query
      # @yieldreturn [Net::HTTPResponse] the answer to the one request
      # @return [Net::HTTPResponse]
      # @raise [Exception] what the request raises, which clears the delay
      # @api private
      def through(key)
        wait(key)
        begin
          response = yield
        ensure
          response&.code == '429' ? refused(key, response['Retry-After']) : cleared(key)
        end
        response
      end

      private

      # @param key [String]
      # @return [void]
      # @api private
      def wait(key)
        state = @lock.synchronize { @state[key] }
        return unless state

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:at]
        pause = self.class.delay(failures: state[:failures], retry_after: state[:retry_after], elapsed:, draw: rand)
        sleep(pause) if pause.positive?
      end

      # @param key [String]
      # @param header [String, nil] the 429's Retry-After
      # @return [void]
      # @api private
      def refused(key, header)
        @lock.synchronize do
          failures = @state.fetch(key, { failures: 0 })[:failures] + 1
          @state[key] = { failures:, retry_after: self.class.retry_after(header),
                          at: Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        end
      end

      # @param key [String]
      # @return [void]
      # @api private
      def cleared(key) = @lock.synchronize { @state.delete(key) }
    end
  end
end
