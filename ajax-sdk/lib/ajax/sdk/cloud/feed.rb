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
          @newest = nil
          @read = false
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

          @tracker.apply(source, message).each(&)
        end

        def follow(source)
          delay = 1
          loop { delay = pause(receive(source) ? 1 : delay) }
        rescue Stop
          nil
        rescue StandardError => e
          @queue << [source, e]
        end

        # @return [Boolean] whether a message came before the stream ended or broke
        def receive(source)
          received = false
          listen(source) { received = true }
          received
        end

        def listen(source)
          catch_up if source == :notifications
          subscribe(source) do |message|
            yield
            remember(stream_marks(message)) if source == :notifications
            @queue << [source, message]
          end
        rescue *RETRIABLE
          nil
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

        # The notification stream has no snapshot. Before its first opening, the thread notes the newest notification;
        # before each reopening, it reads back the ones created since, as the app pages: from one outside a group.
        def catch_up
          return note_newest unless @read

          loop do
            page = @client.notifications(@space_id, limit: PAGE, newer_than: @newest&.last)
            @queue << [:notifications, created(page.reverse)] unless page.empty?
            top = page.reject(&:parent_id)
            remember(page_marks(top))
            break if top.size < PAGE
          end
        end

        def note_newest
          remember(page_marks(@client.notifications(@space_id, limit: 1).reject(&:parent_id)))
          @read = true
        end

        def remember(marks) = @newest = [@newest, *marks].compact.max_by(&:first)

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
