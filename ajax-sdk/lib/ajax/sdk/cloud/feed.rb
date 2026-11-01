# frozen_string_literal: true

require_relative 'tracker'

module Ajax
  module Sdk
    module Cloud
      # Follows one space live. One thread per stream (+SpaceService/stream+, +streamUserSpaces+,
      # +stream_light_devices+ and +NotificationLogService/streamUpdates+) pushes its messages onto a queue; the
      # caller's thread alone applies them to a {Tracker} and yields the {Event}s. The feed ends with the first
      # stream that ends, and raises what breaks one; reopening it is the caller's, with the same tracker.
      class Feed
        SOURCES = %i[space summary devices notifications].freeze
        PAGE = 20
        SPACE = Messages::Api::Mobile::V2::Common::Space
        ORIGIN = Messages::Api::Ecosystem::V2::Communicationsvc::Mobile::Commonmodels::Notification
        LOG = Messages::Api::Mobile::V2::Notification
        private_constant :SOURCES, :PAGE, :SPACE, :ORIGIN, :LOG

        # Raised into a stream's thread to end it.
        class Stop < StandardError; end
        private_constant :Stop

        # @param client [Client]
        # @param space_id [String]
        # @param tracker [Tracker] the state to compare the streams with
        def initialize(client, space_id, tracker:)
          @client = client
          @space_id = space_id
          @tracker = tracker
          @queue = Queue.new
        end

        # Blocks and yields every event until a stream ends; an exception of the block, or leaving it, closes the
        # four streams.
        #
        # @yieldparam event [Event]
        # @return [void]
        # @raise [RefusedError] when a stream answers a failure
        # @raise [GRPC::BadStatus] when a stream breaks
        def each(&)
          threads = SOURCES.map { |source| Thread.new { follow(source) }.tap { it.name = "ajax-feed-#{source}" } }
          loop do
            source, message, marks = @queue.pop
            break if message == :ended

            deliver(source, message, marks, &)
          end
        ensure
          threads&.each { it.raise(Stop) }
          threads&.each(&:join)
        end

        private

        # A notification counts as read once the caller gets it, so a feed reopened with the tracker reads back the
        # ones still queued when this one ended.
        def deliver(source, message, marks, &)
          raise message if message.is_a?(Exception)

          events = @tracker.apply(source, message)
          @tracker.remember(marks) if marks
          events.each(&)
        end

        def follow(source)
          catch_up if source == :notifications
          subscribe(source) { @queue << [source, it, (stream_marks(it) if source == :notifications)] }
          @queue << [source, :ended]
        rescue Stop
          nil
        rescue StandardError => e
          @queue << [source, e]
        end

        def subscribe(source, &)
          case source
          when :space then @client.space_stream(space_locator: SPACE::SpaceLocator.new(space_id: @space_id), &)
          when :summary then @client.space_stream_user_spaces(&)
          when :devices then @client.stream_light_devices(space_id: @space_id, &)
          else @client.notification_log_stream_updates(origin: ORIGIN::NotificationOriginId.new(space_id: @space_id), &)
          end
        end

        # The notification stream has no snapshot. The app pages from a notification outside a group.
        def catch_up
          return note_newest unless @tracker.read?

          cursor = @tracker.newest
          loop do
            page = @client.notifications(@space_id, limit: PAGE, newer_than: cursor&.last)
            marks = page_marks(page.reject(&:parent_id))
            @queue << [:notifications, created(page.reverse), marks] unless page.empty?
            break if marks.size < PAGE

            cursor = marks.max_by(&:first)
          end
        end

        def note_newest = @tracker.remember(page_marks(@client.notifications(@space_id, limit: 1).reject(&:parent_id)))

        def page_marks(notifications) = notifications.map { [it.time.to_f, it.token] }

        def stream_marks(message)
          message.events.filter_map { it.notification_created || it.notification_updated }
                 .map { [it.server_timestamp.to_f, it.universal_token] }
        end

        def created(page)
          LOG::StreamNotificationLogResponse::Success.from({ events: page.map { { notification_created: it.raw } } })
        end
      end
    end
  end
end
