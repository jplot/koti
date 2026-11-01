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

      # The cloud archive's fragments of a time range, and +utc_offsets+: the UTC offset in seconds in force from
      # each time on, which the app's timeline reads to show the local time.
      FragmentList = Data.define(:fragments, :utc_offsets) do
        # @param answer [Data] the success of +find_all_cloud_archive_video_fragments_info+ or of its metadata twin
        # @return [FragmentList]
        def self.from(answer)
          new(fragments: answer.fragments_info.map { Fragment.from(it) },
              utc_offsets: answer.time_zone_map.to_h { [it.timestamp, it.offset] })
        end
      end

      # A cloud archive content stream of a channel, as the app's player reads it: after the init, each +get+ asks
      # for the addresses of some fragments under a tag the answers carry back. The stream itself carries no media.
      # It lasts until {#close}. Requests come from one thread at a time, as the app's do; {#each} runs on its own.
      class CloudContent
        # @param exchange [Exchange] the content call, its init written
        # @param request [Class] the request message of the call
        def initialize(exchange, request)
          @exchange = exchange
          @request = request
        end

        # @yieldparam content [Data] each answer: a +FragmentContent+ or +FragmentPartContent+ (its +tag+, +status+,
        #   +content_url+, the +content_url_headers+ a part is fetched with, +content_url_expires_at+), or the video
        #   stream's +Init+
        # @return [nil, Enumerator] an Enumerator of the answers when no block is given
        # @raise [ReadError] when the cloud refuses (+:playback_limit_exceeded+, +:cloud_archive_not_found+…)
        def each
          return enum_for(:each) unless block_given?

          @exchange.each { |success| success.content_case&.then { yield success.public_send(it) } }
        end

        # @return [nil]
        def close = @exchange.close

        private

        def ask(tag, entries)
          @exchange.write(@request.new(get: @request::Get.new(tag: tag.to_s, entries:)))
          tag.to_s
        end
      end

      # The video content stream: its addresses serve fragmented MP4, each played by the app as its own source. Its
      # tag is a generation, as the app's: every request carries the current one, from -1, and {#seek} moves it on,
      # so the answers to the requests made before a seek come with an older tag and can be dropped as late.
      class CloudArchive < CloudContent
        # The stream's request message, whose init {Shortcuts::Archive#cloud_archive} writes.
        REQUEST = Messages::Api::Ecosystem::V3::Mobilegwsvc::Service::StreamCloudArchiveVideoFragmentsContent::
                  StreamCloudArchiveVideoFragmentsContentRequest
        DAY = 86_400
        private_constant :DAY

        # The days a channel's calendar marks as recorded, read as the app's +b151+ reads them: a byte per day from
        # +start_day+, each recorded day shifted, in days, by the offsets of the last +tz_map+ entry not after it
        # (none, no date), then each date once, in that order.
        #
        # @param calendar [Data] a +Calendar+
        # @return [Array<Date>] UTC dates
        def self.days(calendar)
          entries = calendar.tz_map.each_with_index.sort_by { |entry, index| [entry.day.to_i, index] }.map(&:first)
          recorded(calendar).flat_map { shifted(it, entries.reverse) }.uniq.map { Time.at(it, in: 'UTC').to_date }
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

        # @param exchange [Exchange] the video content call, its init written
        def initialize(exchange)
          super(exchange, REQUEST)
          @tag = -1
        end

        # @param fragment_ids [Array<Integer>] {Fragment#id}s
        # @return [String] the tag of the request
        def get(*fragment_ids) = ask(@tag, fragment_ids.map { REQUEST::Get::Entry.new(fragment_id: it) })

        # Asks for a fragment from an offset, as the app does to seek on the sub stream.
        #
        # @param fragment_id [Integer]
        # @param offset [Float] seconds from the start of the fragment, sent in whole milliseconds as the app does
        # @return [String] the tag of the request
        def get_part(fragment_id, offset)
          part = REQUEST::Get::FragmentPart.new(fragment_id:, offset: (offset * 1000).round * 1000)
          ask(@tag, [REQUEST::Get::Entry.new(fragment_part: part)])
        end

        # Moves the tag on, as the app does when the user seeks.
        #
        # @return [String] the new tag
        def seek = (@tag += 1).to_s
      end

      # The metadata content stream: each address serves the gzip of
      # +StreamCloudArchiveMetadataFragmentsContentResponse.FragmentContent.Frames+. Each request takes the next tag,
      # from 0, as the app's do.
      class CloudMetadata < CloudContent
        # The stream's request message, whose init {Shortcuts::Archive#cloud_metadata} writes.
        REQUEST = Messages::Api::Ecosystem::V3::Mobilegwsvc::Service::StreamCloudArchiveMetadataFragmentsContent::
                  StreamCloudArchiveMetadataFragmentsContentRequest

        # @param exchange [Exchange] the metadata content call, its init written
        def initialize(exchange)
          super(exchange, REQUEST)
          @tag = 0
        end

        # @param fragment_ids [Array<Integer>] {Fragment#id}s
        # @return [String] the tag of the request
        def get(*fragment_ids)
          tag = @tag
          @tag += 1
          ask(tag, fragment_ids.map { REQUEST::Get::Entry.new(fragment_id: it) })
        end
      end
    end
  end
end
