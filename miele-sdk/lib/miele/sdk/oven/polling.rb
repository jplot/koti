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
        private_constant :POLLING_DELAY, :RETRY_BASE

        private

        # @param timeout [Integer] the seconds the app waits
        # @yieldreturn [Object, nil] what a read shows, nil or false to read again
        # @return [Object, nil] the first value the block gives, nil once the timeout is up
        # @raise [ResponseError] for a read refused with a 4xx
        def poll(timeout, &)
          waited = 0.0
          failures = 0
          while waited < timeout
            answered, found = polled(&)
            return found if found

            failures = answered ? 0 : failures + 1
            waited += pause(failures, waited, timeout)
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
        # @param waited [Float] seconds since the wait began
        # @param timeout [Integer]
        # @return [Integer, Float] the seconds before the next read, slept unless past the timeout
        def pause(failures, waited, timeout)
          delay = failures.zero? ? POLLING_DELAY : RETRY_BASE**failures
          @sleeper.call(delay) if waited + delay < timeout
          delay
        end
      end
    end
  end
end
