# frozen_string_literal: true

module Miele
  module Sdk
    # The requests the app's actions send again on purpose, for {Appliance}: every other one goes out once.
    module Resends
      private

      # ExecuteSequentiallyUntilTrue sends a switch step through Rx's Retry(3): three attempts back to back,
      # whatever fails, a 400 included.
      #
      # @yieldreturn [Object] one attempt of the step
      # @return [Object] what the attempt that succeeds gives
      # @raise [Error] what the third attempt raises
      def three_attempts
        failures = 0
        begin
          yield
        rescue Error
          failures += 1
          retry if failures < 3
          raise
        end
      end

      # RetryOnRestException: a refusal other than a 4xx, or a connection lost (the app's RestException of status
      # 0), goes out again 1.5^n s later, 15 s past the sixth (CalculateDelayUntilMax), with no limit but the
      # action's Timeout.
      #
      # @param retries [Integer, Float] how many times the module's helper sends it again at most
      # @param delay [Integer, nil] the seconds its helper waits before each, nil for those 1.5^n
      # @param within [Numeric] the seconds the action's Timeout leaves its waits
      # @param waits [Array<Numeric>] where its waits are counted, for the action's next steps to count on
      # @yieldreturn [Object] one attempt
      # @return [Object] what the attempt that succeeds gives
      # @raise [Error] the first error the app does not send again, or the last once the next wait would end
      #   +within+
      def resent(retries: Float::INFINITY, delay: nil, within: Float::INFINITY, waits: [])
        yield
      rescue ResponseError, ConnectionError => e
        pause = delay || (waits.size < 6 ? 1.5**(waits.size + 1) : 15)
        raise unless waits.size < retries && resent?(e) && waits.sum + pause < within

        @sleeper.call(pause)
        waits << pause
        retry
      end

      # PollingAccessStrategy reads the resource again 3 s after each answer (RequestHelper.PollingDelay) until it
      # shows the action done, within the action's Timeout; an error ends it.
      #
      # @param waits [Array<Numeric>] the seconds the action has waited, the polls' added
      # @param within [Numeric] the action's Timeout, in seconds
      # @param first [Numeric] the seconds before the first read
      # @yieldreturn [Boolean] whether a read shows the action done
      # @return [void]
      # @raise [ActionFailedError] once the next read would come after +within+
      def polled(waits, within:, first: 0)
        delay = first
        while waits.sum + delay < within
          sleep_counted(waits, delay)
          return if yield

          delay = 3
        end
        raise ActionFailedError, "the appliance did not show what was written within #{within} s"
      end

      # @param waits [Array<Numeric>]
      # @param seconds [Numeric]
      # @return [void]
      def sleep_counted(waits, seconds)
        return if seconds.zero?

        @sleeper.call(seconds)
        waits << seconds
      end

      # A timeout is the app's TaskCanceledException, which RetryOnRestException never sends again.
      #
      # @param error [ResponseError, ConnectionError]
      # @return [Boolean] whether the app's RestException would carry a status outside 400 to 499
      def resent?(error)
        return !(400..499).cover?(error.status) if error.is_a?(ResponseError)

        !error.cause.is_a?(Timeout::Error)
      end
    end
  end
end
