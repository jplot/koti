# frozen_string_literal: true

module Miele
  module Sdk
    class Oven < Appliance
      # How the app's oven module waits on a polled leaf (Dop2ReadHelper.ObserveViaPolling): a read every 3 s
      # (PollingDelay), and a refusal other than a 4xx read again 1.5^n s later, the n-th in a row
      # (RetryOnRestException's CalculateDelay).
      module Polling
        POLLING_DELAY = 3
        RETRY_BASE = 1.5
        # The app's ActionExecutionTimeout, in seconds.
        ACTION_TIMEOUT = 15
        private_constant :POLLING_DELAY, :RETRY_BASE

        private

        # @param timeout [Integer] the seconds the app waits, on the wall clock as its Timeout
        # @param since [Float] when the wait began, on the appliance's monotonic clock
        # @yieldreturn [Object, nil] what a read shows, nil or false to read again
        # @return [Object, nil] the first value the block gives, nil once the timeout is up
        # @raise [ResponseError] for a read refused with a 4xx
        def poll(timeout, since: @clock.call, &)
          failures = 0
          while @clock.call - since < timeout
            answered, found = polled(&)
            return found if found

            failures = answered ? 0 : failures + 1
            break unless paused?(failures, since, timeout)
          end
        end

        # RetryOnRestException ends the app's poll on a 4xx alone.
        #
        # @yieldreturn [Object] what a read shows
        # @return [Array(Boolean, Object)] whether the read was answered, and what the block made of it
        def polled
          [true, yield]
        rescue ResponseError => e
          raise if (400..499).cover?(e.status)

          [false, nil]
        end

        # @param failures [Integer] the reads refused in a row
        # @param since [Float] when the wait began
        # @param timeout [Numeric]
        # @return [Boolean] whether the delay before the next read ends within the timeout, slept then
        def paused?(failures, since, timeout)
          delay = failures.zero? ? POLLING_DELAY : RETRY_BASE**failures
          return false if @clock.call - since + delay >= timeout

          @sleeper.call(delay)
          true
        end
      end
    end
  end
end
