# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # Con@ctivity Plus as the app's Con@ctivity module writes it and waits for it to show.
      module Conactivity
        # Con@ctivity Plus: the hood follows one more hob. {Readings#connectivity_plus} gives whether the app offers
        # it.
        #
        # @param hob [String] its fabrication number
        # @return [void]
        # @raise [ResponseError, ConnectionError] a 4xx or a timeout at once, another refusal at the fourth attempt
        # @raise [ActionFailedError] when +services+ do not list the hob within the app's 15 s
        # @api public
        def connect_hob(hob) = update_connectivity_plus(hob, true)

        # @param hob [String] its fabrication number
        # @return [void]
        # @raise [ResponseError, ConnectionError] a 4xx or a timeout at once, another refusal at the fourth attempt
        # @raise [ActionFailedError] when +services+ still list the hob after the app's 15 s
        # @api public
        def disconnect_hob(hob) = update_connectivity_plus(hob, false)

        private

        # The app changes one hob in the list +services+ shows and derives +activated+ from what is left
        # (UpdateConactivityPlusSettingsHelper), then waits for +services+ to show it (ConnectionIsSet), all within
        # the 15 s of UpdateConactivitySettingsAction.
        #
        # @param hob [String]
        # @param connect [Boolean] whether the hood follows it
        # @return [void]
        # @raise [ActionFailedError]
        def update_connectivity_plus(hob, connect) = within(15) { |since| write_connectivity_plus(hob, connect, since) }

        # @param hob [String]
        # @param connect [Boolean]
        # @param since [Float] when the action began
        # @return [void]
        # @raise [ActionFailedError]
        def write_connectivity_plus(hob, connect, since)
          read = nil #: [Array[String]?, Float]?
          last = resent(retries: 3, delay: 2, since:) do
            current = read = plus_read(read)
            sources = followed(Array(current.first), hob, connect)
            body = JSON.generate('activated' => sources.any?, 'sourceDeviceIds' => sources)
            send_request(:put, "/Devices/#{fab}/services/ConnectivityPlus", body:)
            current
          end
          plus_shown(last, since, hob, connect)
        end

        # ObserveServices polls through one loop per path that outlives its subscribers until its 3 s wait ends
        # (FetchRepeatedlyWithCaching): an attempt within 3 s of the last answer gets that answer again.
        #
        # @param last [Array(Array<String>, Float), nil] the hobs the last read listed, and when it was answered
        # @return [Array(Array<String>, Float)]
        def plus_read(last)
          return last if last && @clock.call - last.last < 3

          sources = connectivity_plus&.sources
          [sources, @clock.call]
        end

        # ConnectionIsSet joins that loop: it checks the answer the loop holds, then reads 3 s after it, at once
        # once the loop has ended.
        #
        # @param read [Array(Array<String>, Float)] the last read
        # @param since [Float] when the action began
        # @param hob [String]
        # @param connect [Boolean]
        # @return [void]
        # @raise [ActionFailedError]
        def plus_shown(read, since, hob, connect)
          sources, read_at = read
          wait = 3.0 - (@clock.call - read_at)
          return if wait.positive? && sources&.include?(hob) == connect

          poll_until_shown(since:, within: 15, first: wait.positive? ? wait : 0) do
            connectivity_plus&.sources&.include?(hob) == connect
          end
        end

        # @param sources [Array<String>] the hobs followed
        # @param hob [String]
        # @param connect [Boolean]
        # @return [Array<String>] those to follow
        def followed(sources, hob, connect) = connect ? (sources + [hob]).uniq : sources - [hob]
      end
    end
  end
end
