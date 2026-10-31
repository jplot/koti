# frozen_string_literal: true

module Miele
  module Sdk
    module Events
      # Several event sources at once: each runs on a thread of its own and their events reach the calling
      # thread. When the block breaks or raises, the threads stop and each source cleans up.
      class Merge
        # @param sources [Array<#each>] such as a {Listener} and a {CloudStream}
        def initialize(sources)
          @sources = sources
        end

        # @yieldparam event [Event]
        # @return [Enumerator::Lazy<Event>, Object] the events without a block, else what +break+ returns
        # @raise [StandardError] what a source raises
        # @api public
        def each(&)
          return to_enum(:each).lazy unless block_given?
          return @sources.fetch(0).each(&) if @sources.one?

          merged(&)
        end

        private

        # @yieldparam event [Event]
        # @return [Object] what +break+ returns
        def merged
          queue = Thread::Queue.new
          threads = @sources.map { |source| Thread.new { feed(source, queue) } }
          loop { yield take(queue) }
        ensure
          threads&.each(&:kill)&.each(&:join)
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
