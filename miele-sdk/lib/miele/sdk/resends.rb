# frozen_string_literal: true

module Miele
  module Sdk
    # The requests the app's actions send again on purpose, for {Appliance}: every other one goes out once.
    module Resends
      # The clock an appliance measures the app's timeouts on unless given one: seconds, monotonic.
      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      # The app gives each action a token of its own: its deadline lives with the fiber that runs it, never on an
      # appliance that several threads share.
      DEADLINE = :miele_sdk_action_deadline
      private_constant :DEADLINE

      private

      # The app sends these requests with the action's token, which it cancels when the action's Timeout ends.
      #
      # @param seconds [Numeric]
      # @yieldparam since [Float] when the action began, on the appliance's monotonic clock
      # @return [Object] what the block gives
      def within(seconds)
        since = @clock.call
        outer = Thread.current[DEADLINE]
        Thread.current[DEADLINE] = since + seconds
        yield since
      ensure
        Thread.current[DEADLINE] = outer
      end

      # @param timeout [Numeric, nil] the seconds the app gives the request itself
      # @return [Numeric, nil] those, or the time the action has left when less
      # @raise [ActionFailedError] without sending, when the action has no time left: its token is cancelled
      def request_timeout(timeout)
        deadline = Thread.current[DEADLINE] #: Float?
        return timeout unless deadline

        left = deadline - @clock.call
        raise ActionFailedError, "the action ran out of the app's time for it" unless left.positive?

        [timeout, left].compact.min
      end

      # For the requests the app sends inside an action with its caller's token, which the action's Timeout leaves
      # alone: they keep their own timeout.
      #
      # @return [Object] what the block gives
      def uncapped
        outer = Thread.current[DEADLINE]
        Thread.current[DEADLINE] = nil
        yield
      ensure
        Thread.current[DEADLINE] = outer
      end

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
      # @param within [Numeric] the seconds of the action's Timeout, a wall-clock bound as the app's
      # @param since [Numeric] when the action began, on the appliance's monotonic clock
      # @yieldreturn [Object] one attempt
      # @return [Object] what the attempt that succeeds gives
      # @raise [Error] the first error the app does not send again, or the last once the next wait would end
      #   +within+
      def resent(retries: Float::INFINITY, delay: nil, within: Float::INFINITY, since: @clock.call)
        done = 0
        begin
          yield
        rescue ResponseError, ConnectionError => e
          pause = delay || (done < 6 ? 1.5**(done + 1) : 15)
          raise unless done < retries && resent?(e) && @clock.call - since + pause < within

          @sleeper.call(pause)
          done += 1
          retry
        end
      end

      # PollingAccessStrategy reads the resource again 3 s after each answer (RequestHelper.PollingDelay) until it
      # shows the action done, within the action's Timeout; an error ends it.
      #
      # @param since [Numeric] when the action began, on the appliance's monotonic clock
      # @param within [Numeric] the action's Timeout, in seconds
      # @param first [Numeric] the seconds before the first read
      # @yieldreturn [Boolean] whether a read shows the action done
      # @return [void]
      # @raise [ActionFailedError] once the next read would come after +within+
      def poll_until_shown(since:, within:, first: 0)
        delay = first
        while @clock.call - since + delay < within
          @sleeper.call(delay) if delay.positive?
          return if yield

          delay = 3
        end
        raise ActionFailedError, "the appliance did not show what was written within #{within} s"
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
