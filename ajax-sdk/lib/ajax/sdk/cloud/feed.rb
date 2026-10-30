# frozen_string_literal: true

require_relative 'tracker'

module Ajax
  module Sdk
    module Cloud
      # Follows one space live. One thread per stream (+SpaceService/stream+, +streamUserSpaces+,
      # +stream_light_devices+ and +NotificationLogService/streamUpdates+) pushes its messages onto a queue; the
      # caller's thread alone applies them to a {Tracker} and yields the {Event}s. A stream reopens after a retriable
      # error or a normal end, 1, 2, 4, 8, 16 then 30 seconds later, back to 1 second at its first message.
      class Feed
        SOURCES = %i[space summary devices notifications].freeze
        # The app gives up on INTERNAL after 3 attempts; a feed lasts, so it retries them all.
        RETRIABLE = [GRPC::Unavailable, GRPC::DeadlineExceeded, GRPC::Internal, GRPC::Cancelled, GRPC::Unknown,
                     GRPC::ResourceExhausted, GRPC::Unauthenticated].freeze
        MAX_DELAY = 30
        PAGE = 20
        SPACE = Messages::Api::Mobile::V2::Common::Space
        ORIGIN = Messages::Api::Ecosystem::V2::Communicationsvc::Mobile::Commonmodels::Notification
        LOG = Messages::Api::Mobile::V2::Notification
        private_constant :SOURCES, :RETRIABLE, :MAX_DELAY, :PAGE, :SPACE, :ORIGIN, :LOG

        # Raised into a stream's thread to end it.
        class Stop < StandardError; end
        private_constant :Stop

        # @param client [Client]
        # @param space_id [String]
        # @param sleeper [#call] waits the given number of seconds before a stream reopens
        def initialize(client, space_id, sleeper:)
          @client = client
          @space_id = space_id
          @sleeper = sleeper
          @tracker = Tracker.new(space_id)
          @queue = Queue.new
        end

        # Blocks and yields every event; an exception of the block, or leaving it, closes the four streams.
        #
        # @yieldparam event [Event]
        # @return [void]
        # @raise [RefusedError] when a stream answers a failure
        def each(&)
          threads = SOURCES.map { |source| Thread.new { follow(source) }.tap { it.name = "ajax-feed-#{source}" } }
          loop do
            source, message = @queue.pop
            deliver(source, message, &)
          end
        ensure
          threads&.each { it.raise(Stop) }
          threads&.each(&:join)
        end

        private

        def deliver(source, message, &)
          raise message if message.is_a?(Exception)

          (message == :reopened ? catch_up : @tracker.apply(source, message)).each(&)
        end

        def follow(source)
          delay = 1
          loop do
            delay = pause(receive(source) ? 1 : delay)
            @queue << [source, :reopened] if source == :notifications
          end
        rescue Stop
          nil
        rescue StandardError => e
          @queue << [source, e]
        end

        # @return [Boolean] whether a message came before the stream ended or broke
        def receive(source)
          received = false
          begin
            subscribe(source) do |message|
              received = true
              @queue << [source, message]
            end
          rescue *RETRIABLE
            nil
          end
          received
        end

        def subscribe(source, &)
          case source
          when :space then @client.space_stream(space_locator: SPACE::SpaceLocator.new(space_id: @space_id), &)
          when :summary then @client.space_stream_user_spaces(&)
          when :devices then @client.stream_light_devices(space_id: @space_id, &)
          else @client.notification_log_stream_updates(origin: ORIGIN::NotificationOriginId.new(space_id: @space_id), &)
          end
        end

        def pause(delay)
          @sleeper.call(delay)
          [delay * 2, MAX_DELAY].min
        end

        # The notification stream has no snapshot: what it missed is read back, page by page, from the newest kept.
        def catch_up
          token = @tracker.newest_token or return []
          events = [] #: Array[Event]
          loop do
            page = @client.notifications(@space_id, limit: PAGE, newer_than: token)
            events.concat(@tracker.apply(:notifications, created(page)))
            top = page.reject(&:parent_id)
            break if top.size < PAGE

            token = top.first&.token
          end
          events
        end

        def created(page)
          LOG::StreamNotificationLogResponse::Success.from({ events: page.map { { notification_created: it.raw } } })
        end
      end
    end
  end
end
