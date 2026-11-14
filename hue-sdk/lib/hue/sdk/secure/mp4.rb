# frozen_string_literal: true

require 'tmpdir'

module Hue
  module Sdk
    module Secure
      # The MP4 media of the clips, read and written by GPAC through files of a temporary folder: the gem changes the
      # data of the samples, GPAC the boxes around them. Never tested on a camera's own files.
      module Mp4
        # One sample, as GPAC reads it.
        Sample = Data.define(:data, :dts, :cts_offset, :is_rap, :duration, :description)

        # The samples of one track of a segment, and the decode time of its first one.
        Track = Data.define(:id, :decode_time, :samples)

        module_function

        # Writes the segment again, each sample's data replaced by the block's: GPAC writes the boxes, the moof keeps
        # its sequence number and each track its decode times.
        #
        # @param segment [String] a media segment of fragmented MP4
        # @param init [String] its initialization segment
        # @yieldparam data [String] the data of a sample
        # @yieldreturn [String] the data to write instead
        # @return [String]
        # @raise [E2eeError] if GPAC cannot read or write it
        def segment(segment, init:, &)
          files(segment, init) { |paths| written(paths, sequence(segment), tracks(paths, &)) }
        end

        # @param bytes [String]
        # @return [Boolean] whether it is a media segment, rather than an initialization segment or a playlist
        def media?(bytes)
          require_relative 'gpac'
          Gpac.gf_isom_probe_data(bytes, bytes.bytesize) == Gpac::MEDIA_SEGMENT
        end

        def files(segment, init)
          require_relative 'gpac'
          Dir.mktmpdir('hue-sdk') do |dir|
            paths = { init: File.join(dir, 'init.mp4'), segment: File.join(dir, 'segment.m4s'), dir: }
            File.binwrite(paths[:init], init)
            File.binwrite(paths[:segment], segment)
            yield paths
          end
        end

        def tracks(paths, &)
          reader = Gpac.opened(paths[:init])
          Gpac.check(Gpac.gf_isom_open_segment(reader, paths[:segment], 0, 0, 0))
          (1..Gpac.gf_isom_get_track_count(reader)).map do |track|
            samples = (1..Gpac.gf_isom_get_sample_count(reader, track)).map { sample(reader, track, it, &) }
            Track.new(id: Gpac.gf_isom_get_track_id(reader, track),
                      decode_time: Gpac.gf_isom_get_current_tfdt(reader, track), samples:)
          end
        ensure
          Gpac.gf_isom_close(reader) if reader
        end

        def sample(reader, track, number) = Gpac.sample(reader, track, number).then { it.with(data: yield(it.data)) }

        def written(paths, sequence, tracks)
          out = File.join(paths[:dir], 'out.m4s')
          reader = Gpac.opened(paths[:init])
          writer = Gpac.writer(reader, paths[:dir])
          Gpac.started(writer, out, sequence)
          tracks.each { |track| fragment(writer, track) }
          Gpac.closed(writer, tracks.first || raise(E2eeError, 'the segment holds no track'))
          File.binread(out)
        ensure
          Gpac.gf_isom_close(writer) if writer
          Gpac.gf_isom_close(reader) if reader
        end

        def fragment(writer, track)
          Gpac.check(Gpac.gf_isom_set_traf_base_media_decode_time(writer, track.id, track.decode_time))
          track.samples.each { Gpac.add(writer, track.id, it) }
        end

        # GPAC documents no reader of the moof's sequence number.
        def sequence(segment)
          at = segment.index('mfhd') or raise E2eeError, 'the segment has no movie fragment header'
          segment.byteslice(at + 8, 4).to_s.unpack1('N').to_i
        end

        private_class_method :files, :tracks, :sample, :written, :fragment, :sequence
      end
    end
  end
end
