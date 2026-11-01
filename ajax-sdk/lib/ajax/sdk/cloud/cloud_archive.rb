# frozen_string_literal: true

require 'date'

module Ajax
  module Sdk
    module Cloud
      # A recorded fragment of a channel in the cloud archive: its +id+, its +start+ and its +duration+ in seconds.
      Fragment = Data.define(:id, :start, :duration) do
        # @param info [Data] a +VideoFragmentInfo+ or a +MetadataFragmentInfo+
        # @return [Fragment]
        def self.from(info) = new(id: info.fragment_id, start: info.timestamp, duration: info.duration)
      end

      # The cloud archive content stream of a channel, as the app's player reads it: after the init, each {#get}
      # asks for the addresses of some fragments, under a tag the answers carry back. The addresses are HTTPS, the
      # video ones serve fragmented MP4 and the metadata ones a gzip of
      # +StreamCloudArchiveMetadataFragmentsContentResponse.FragmentContent.Frames+; the stream itself carries no
      # media. It lasts until {#close}.
      class CloudArchive
        DAY = 86_400
        private_constant :DAY

        # The days a channel's calendar marks as recorded, read as the app's +b151+ reads them: a byte per day from
        # +start_day+, and the last +tz_map+ entry not after a recorded day shifts it by each of its offsets, in days.
        #
        # @param calendar [Data] a +Calendar+
        # @return [Array<Date>]
        def self.days(calendar)
          entries = calendar.tz_map.sort_by { it.day.to_i }.reverse
          recorded(calendar).flat_map { shifted(it, entries) }.uniq.sort.map { Time.at(it, in: 'UTC').to_date }
        end

        # @api private
        def self.recorded(calendar)
          start = calendar.start_day.to_i
          calendar.days.bytes.each_with_index.filter_map { |byte, index| start + (index * DAY) unless byte.zero? }
        end

        # @api private
        def self.shifted(day, entries)
          entry = entries.find { it.day.to_i <= day }
          entry ? entry.offsets.map { day + (it * DAY) } : []
        end
        private_class_method :recorded, :shifted

        # @param exchange [Exchange] the content call, its init written
        # @param request [Class] the request message of the call, video or metadata
        def initialize(exchange, request)
          @exchange = exchange
          @request = request
          @lock = Mutex.new
          @tag = 0
        end

        # @param fragment_ids [Array<Integer>] {Fragment#id}s
        # @return [String] the tag of the request
        def get(*fragment_ids) = ask(fragment_ids.map { @request::Get::Entry.new(fragment_id: it) })

        # Asks for a video fragment from an offset, as the app does to seek on the sub stream.
        #
        # @param fragment_id [Integer]
        # @param offset [Float] seconds from the start of the fragment
        # @return [String] the tag of the request
        def get_part(fragment_id, offset)
          part = @request::Get::FragmentPart.new(fragment_id:, offset: (offset * 1_000_000).to_i)
          ask([@request::Get::Entry.new(fragment_part: part)])
        end

        # @yieldparam content [Data] each answer: a +FragmentContent+ or +FragmentPartContent+ (its +tag+, +status+,
        #   +content_url+, the +content_url_headers+ a part is fetched with, +content_url_expires_at+), or the video
        #   stream's +Init+
        # @return [nil, Enumerator] an Enumerator of the answers when no block is given
        # @raise [ReadError] when the cloud refuses (+:playback_limit_exceeded+, +:cloud_archive_not_found+…)
        def each
          return enum_for(:each) unless block_given?

          @exchange.each { |success| yield success.public_send(success.content_case) }
        end

        # @return [nil]
        def close = @exchange.close

        private

        def ask(entries)
          tag = @lock.synchronize { @tag += 1 }.to_s
          @exchange.write(@request.new(get: @request::Get.new(tag:, entries:)))
          tag
        end
      end
    end
  end
end
