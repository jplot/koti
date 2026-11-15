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
      # 0), goes out again 1.5^n s later, 15 s past the sixth (CalculateDelayUntilMax), with no limit.
      #
      # @yieldreturn [Object] one attempt
      # @return [Object] what the attempt that succeeds gives
      # @raise [Error] the first error the app does not send again
      def resent
        retries = 0
        begin
          yield
        rescue ResponseError, ConnectionError => e
          raise unless resent?(e)

          retries += 1
          @sleeper.call(retries > 6 ? 15 : 1.5**retries)
          retry
        end
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
