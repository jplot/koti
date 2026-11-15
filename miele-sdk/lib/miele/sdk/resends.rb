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
    end
  end
end
