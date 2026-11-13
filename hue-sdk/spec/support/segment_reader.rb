# frozen_string_literal: true

# Reads back what a player relies on in an fMP4 media segment, to check a rewrite: each sample through GPAC, and the
# moof's sequence number and decode times from the boxes themselves.
module SegmentReader
  module_function

  def samples(segment, init:)
    require 'hue/sdk/secure/gpac'
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, 'init.mp4'), init)
      File.binwrite(File.join(dir, 'segment.m4s'), segment)
      read(File.join(dir, 'init.mp4'), File.join(dir, 'segment.m4s'))
    end
  end

  def read(init, segment)
    gpac = Hue::Sdk::Secure::Gpac
    reader = gpac.opened(init)
    gpac.check(gpac.gf_isom_open_segment(reader, segment, 0, 0, 0))
    (1..gpac.gf_isom_get_track_count(reader)).flat_map do |track|
      id = gpac.gf_isom_get_track_id(reader, track)
      (1..gpac.gf_isom_get_sample_count(reader, track)).map { [id, *gpac.sample(reader, track, it).to_h.values] }
    end
  ensure
    gpac.gf_isom_close(reader) if reader
  end

  def header(segment)
    moof = box(segment, 'moof', 0, segment.bytesize)
    { sequence: segment.byteslice(box(segment, 'mfhd', moof + 8, segment.bytesize) + 12, 4).unpack1('N'),
      decode_times: decode_times(segment, moof) }
  end

  def decode_times(segment, from)
    times = []
    while (at = segment.index('tfdt', from))
      version = segment.getbyte(at + 4)
      times << (version == 1 ? segment.byteslice(at + 8, 8).unpack1('Q>') : segment.byteslice(at + 8, 4).unpack1('N'))
      from = at + 4
    end
    times
  end

  def box(bytes, type, from, to)
    while from + 8 <= to
      size, name = bytes.byteslice(from, 8).unpack('Na4')
      return from if name == type

      from += size
    end
    raise "no #{type} box"
  end
end
