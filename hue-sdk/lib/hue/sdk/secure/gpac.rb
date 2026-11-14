# frozen_string_literal: true

begin
  require 'ffi'
rescue LoadError
  raise Hue::Sdk::Error, "decrypting Hue Secure clips needs the ffi gem: add gem 'ffi' to your Gemfile"
end

module Hue
  module Sdk
    module Secure
      # Bindings to GPAC's ISO media library, which reads and writes the MP4 files and segments of the clips: the gem
      # replaces their samples and leaves the boxes to GPAC. Found by its name, as the system finds libraries.
      module Gpac
        extend FFI::Library

        begin
          ffi_lib 'gpac'
        rescue LoadError
          raise Error, "decrypting Hue Secure clips needs GPAC's libgpac: install GPAC (libgpac-dev on Ubuntu 24.04)"
        end

        # The first fields of +GF_ISOSample+, the only ones the gem reads or writes: GPAC allocates the whole of it.
        class Sample < FFI::Struct
          layout :data_length, :uint32, :data, :pointer, :dts, :uint64, :cts_offset, :int32, :is_rap, :int
        end

        # What gf_isom_probe_data answers for a media segment.
        MEDIA_SEGMENT = 3

        WRITE = 2
        EDIT = 3
        MOOF_FIRST = 1
        TIGHT = 5
        private_constant :WRITE, :EDIT, :MOOF_FIRST, :TIGHT

        callback :progress, %i[pointer string uint64 uint64], :void
        attach_function :gf_sys_init, %i[int string], :int
        attach_function :gf_set_progress_callback, %i[pointer progress], :void
        attach_function :gf_isom_open, %i[string int string], :pointer
        attach_function :gf_isom_open_progressive, %i[string uint64 uint64 int pointer pointer], :int
        attach_function :gf_isom_open_segment, %i[pointer string uint64 uint64 int], :int
        attach_function :gf_isom_close, %i[pointer], :int
        attach_function :gf_isom_delete, %i[pointer], :void
        attach_function :gf_isom_set_final_name, %i[pointer string], :int
        attach_function :gf_isom_update_sample, %i[pointer uint32 uint32 pointer int], :int
        attach_function :gf_isom_set_storage_mode, %i[pointer int], :int
        attach_function :gf_isom_keep_utc_times, %i[pointer int], :void
        attach_function :gf_isom_probe_data, %i[buffer_in uint32], :uint32
        attach_function :gf_isom_get_timescale, %i[pointer], :uint32
        attach_function :gf_isom_set_timescale, %i[pointer uint32], :int
        attach_function :gf_isom_get_track_count, %i[pointer], :uint32
        attach_function :gf_isom_get_track_id, %i[pointer uint32], :uint32
        attach_function :gf_isom_get_sample_count, %i[pointer uint32], :uint32
        attach_function :gf_isom_get_sample, %i[pointer uint32 uint32 pointer], :pointer
        attach_function :gf_isom_get_sample_duration, %i[pointer uint32 uint32], :uint32
        attach_function :gf_isom_get_current_tfdt, %i[pointer uint32], :uint64
        attach_function :gf_isom_get_sample_sync, %i[pointer uint32 uint32], :int
        attach_function :gf_isom_sample_new, [], :pointer
        attach_function :gf_isom_sample_del, %i[pointer], :void
        attach_function :gf_isom_clone_track, %i[pointer uint32 pointer int pointer], :int
        attach_function :gf_isom_setup_track_fragment, %i[pointer uint32 uint32 uint32 uint32 uint8 uint8 uint16 int],
                        :int
        attach_function :gf_isom_finalize_for_fragment, %i[pointer uint32 int], :int
        attach_function :gf_isom_start_segment, %i[pointer string int], :int
        attach_function :gf_isom_set_next_moof_number, %i[pointer uint32], :void
        attach_function :gf_isom_start_fragment, %i[pointer int], :int
        attach_function :gf_isom_set_traf_base_media_decode_time, %i[pointer uint32 uint64], :int
        attach_function :gf_isom_fragment_add_sample, %i[pointer uint32 pointer uint32 uint32 uint8 uint16 int], :int
        attach_function :gf_isom_close_segment,
                        %i[pointer int32 uint32 uint64 int32 uint64 int int int int uint32 pointer pointer pointer],
                        :int

        # Profile "0" keeps GPAC's configuration in memory: by default GPAC writes one to $HOME/.gpac, and calls exit(1)
        # when it cannot, as under a read-only HOME.
        gf_sys_init(0, '0').zero? or raise Error, 'GPAC cannot start'

        # GPAC draws a progress bar on the process's stderr each time it writes a file, unless a callback takes it.
        SILENT = proc {}
        private_constant :SILENT
        gf_set_progress_callback(nil, SILENT)

        # @param error [Integer] what a GPAC function answered
        # @return [true]
        # @raise [E2eeError] unless GPAC succeeded
        def self.check(error) = error.zero? || raise(E2eeError, "GPAC cannot read or write the clip (error #{error})")

        # @param path [String] an initialization segment
        # @return [FFI::Pointer] the file its media segments open in
        def self.opened(path)
          holder = FFI::MemoryPointer.new(:pointer)
          check(gf_isom_open_progressive(path, 0, 0, 0, holder, FFI::MemoryPointer.new(:uint64)))
          holder.read_pointer
        end

        # The sync flag comes from the boxes: the sample's own IsRAP is what GPAC infers from the data, which is
        # random-looking while sealed (5 video samples in 30 sealed segments read as sync).
        #
        # @param reader [FFI::Pointer]
        # @param track [Integer]
        # @param number [Integer]
        # @return [Mp4::Sample]
        def self.sample(reader, track, number)
          description = FFI::MemoryPointer.new(:uint32)
          pointer = gf_isom_get_sample(reader, track, number, description)
          raise E2eeError, "GPAC cannot read sample #{number} of track #{track}" if pointer.null?

          read = Sample.new(pointer)
          Mp4::Sample.new(data: read[:data].read_bytes(read[:data_length]), dts: read[:dts],
                          cts_offset: read[:cts_offset], is_rap: gf_isom_get_sample_sync(reader, track, number),
                          duration: gf_isom_get_sample_duration(reader, track, number),
                          description: description.read_uint32)
        ensure
          deleted(pointer)
        end

        # A writer of fragments whose tracks are those of the initialization segment the player already has.
        #
        # @param reader [FFI::Pointer] the initialization segment
        # @param dir [String]
        # @return [FFI::Pointer]
        def self.writer(reader, dir)
          writer = gf_isom_open(File.join(dir, 'writer.mp4'), WRITE, dir)
          check(gf_isom_set_timescale(writer, gf_isom_get_timescale(reader)))
          (1..gf_isom_get_track_count(reader)).each do |track|
            check(gf_isom_clone_track(reader, track, writer, 0, FFI::MemoryPointer.new(:uint32)))
            check(gf_isom_setup_track_fragment(writer, gf_isom_get_track_id(reader, track), 1, 0, 0, 0, 0, 0, 1))
          end
          check(gf_isom_finalize_for_fragment(writer, 1, 1))
          writer
        end

        # Starts the segment and its one moof.
        #
        # @param writer [FFI::Pointer]
        # @param out [String] the file of the segment
        # @param sequence [Integer] the sequence number of the moof
        # @return [void]
        def self.started(writer, out, sequence)
          check(gf_isom_start_segment(writer, out, 0))
          gf_isom_set_next_moof_number(writer, sequence)
          check(gf_isom_start_fragment(writer, MOOF_FIRST))
        end

        # Ends the segment, with one sidx on its first track.
        #
        # @param writer [FFI::Pointer]
        # @param first [Mp4::Track]
        # @return [void]
        def self.closed(writer, first)
          check(gf_isom_close_segment(writer, 0, first.id, first.decode_time, 0, 0, 0, 0, 0, 1, 0, nil, nil, nil))
        end

        # @param writer [FFI::Pointer]
        # @param track [Integer]
        # @param sample [Mp4::Sample]
        # @return [void]
        def self.add(writer, track, sample)
          pointer = gf_isom_sample_new
          written = filled(Sample.new(pointer), sample)
          check(gf_isom_fragment_add_sample(writer, track, written, sample.description, sample.duration, 0, 0, 0))
        ensure
          written[:data] = FFI::Pointer::NULL if written
          deleted(pointer)
        end

        # Opens a file to change its samples, and writes it under another name once the block is done: on a failure,
        # GPAC drops it.
        #
        # @param path [String]
        # @param out [String]
        # @param dir [String] for GPAC's own temporary files
        # @yieldparam file [FFI::Pointer]
        # @return [void]
        # @raise [E2eeError] if GPAC cannot read or write it
        def self.edited(path, out, dir)
          file = gf_isom_open(path, EDIT, dir)
          raise E2eeError, 'GPAC cannot read the clip' if file.null?

          begin
            saved_as(file, out)
            yield file
            written = true
          ensure
            gf_isom_delete(file) unless written
          end
          check(gf_isom_close(file))
        end

        # The app keeps the moov before the mdat, one sample per chunk, and the movie's times: GPAC would write the
        # moov last, each track's samples together, and stamp the times.
        #
        # @param file [FFI::Pointer] opened by {edited}
        # @param out [String]
        # @return [void]
        def self.saved_as(file, out)
          check(gf_isom_set_final_name(file, out))
          check(gf_isom_set_storage_mode(file, TIGHT))
          gf_isom_keep_utc_times(file, 1)
        end

        # @param file [FFI::Pointer] opened by {edited}
        # @param track [Integer]
        # @param number [Integer]
        # @param sample [Mp4::Sample] whose data replaces the sample's
        # @return [void]
        def self.replace(file, track, number, sample)
          pointer = gf_isom_sample_new
          written = filled(Sample.new(pointer), sample)
          check(gf_isom_update_sample(file, track, number, written, 1))
        ensure
          written[:data] = FFI::Pointer::NULL if written
          deleted(pointer)
        end

        # @param written [Sample] a sample GPAC allocated
        # @param sample [Mp4::Sample]
        # @return [Sample]
        def self.filled(written, sample)
          written[:data] = FFI::MemoryPointer.from_string(sample.data)
          written[:data_length] = sample.data.bytesize
          %i[dts cts_offset is_rap].each { written[it] = sample.public_send(it) }
          written
        end

        # @param pointer [FFI::Pointer, nil] a sample GPAC allocated
        # @return [void]
        def self.deleted(pointer)
          return if pointer.nil? || pointer.null?

          gf_isom_sample_del(FFI::MemoryPointer.new(:pointer).write_pointer(pointer))
        end
      end
    end
  end
end
