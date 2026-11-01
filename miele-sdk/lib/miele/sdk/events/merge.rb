# frozen_string_literal: true

module Miele
  module Sdk
    module Events
      # Event sources, each read on a thread of its own, even alone: a slow block then holds back neither the
      # cloud websocket's keep-alive nor its reads. Their events reach the calling thread. When the block breaks
      # or raises, the threads stop and each source cleans up.
      class Merge
        # @param sources [Array<#each>] such as a {Listener} and a {CloudStream}
        def initialize(sources)
          @sources = sources
        end

        # @yieldparam event [Event]
        # @return [Enumerator::Lazy<Event>, Object] the events without a block, else what +break+ returns
        # @raise [StandardError] what a source raises, or raises as it cleans up once the block breaks
        # @api public
        def each(&)
          return to_enum(:each).lazy unless block_given?

          merged(&)
        end

        private

        # @yieldparam event [Event]
        # @return [Object] what +break+ returns
        def merged(&)
          queue = Thread::Queue.new
          follow(queue, @sources.map { |source| Thread.new { feed(source, queue) } }, &)
        end

        # @param queue [Thread::Queue]
        # @param threads [Array<Thread>]
        # @yieldparam event [Event]
        # @return [Object] what +break+ returns
        def follow(queue, threads)
          loop { yield take(queue) }
        rescue Exception => e # rubocop:disable Lint/RescueException -- what ended the stream outranks a cleanup
          error = e
          raise
        ensure
          stop(queue, threads, error)
        end

        # A source killed when the block breaks still cleans up, and what that raises lands on the queue: it reaches
        # the caller unless an error already ends the stream.
        #
        # @param queue [Thread::Queue]
        # @param threads [Array<Thread>]
        # @param error [Exception, nil] what ends the stream
        # @return [void]
        def stop(queue, threads, error)
          threads.each(&:kill).each(&:join)
          failure = Array.new(queue.size) { queue.pop }.find { it.is_a?(Exception) }
          raise failure if error.nil? && failure
        end

        # @param source [#each]
        # @param queue [Thread::Queue]
        # @return [void]
        def feed(source, queue)
          source.each { queue << it }
        rescue StandardError => e
          queue << e
        end

        # @param queue [Thread::Queue]
        # @return [Event]
        # @raise [StandardError] what a source raised
        def take(queue)
          item = queue.pop
          raise item if item.is_a?(Exception)

          item
        end
      end
    end
  end
end
