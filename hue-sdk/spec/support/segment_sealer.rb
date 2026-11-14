# frozen_string_literal: true

# Seals each sample of a media segment in place, as a camera writes it, rather than through GPAC: GPAC infers the sync
# flag of a video sample from its data, which sealing makes random. The samples grow by 28 bytes, and the runs' sizes
# and data offsets with them.
class SegmentSealer
  def initialize(segment, &seal)
    @segment = segment
    @seal = seal
    top = boxes(segment, 0, segment.bytesize)
    @moof_at, @moof_size = top.assoc('moof').drop(1)
    @mdat_end = top.assoc('mdat').drop(1).sum
    @moof = segment.byteslice(@moof_at, @moof_size).dup
    @payload = ''.b
  end

  def sealed
    runs.each { seal_run(it) }
    "#{@segment.byteslice(0, @moof_at)}#{@moof}#{[@payload.bytesize + 8].pack('N')}mdat#{@payload}" \
      "#{@segment.byteslice(@mdat_end..)}"
  end

  private

  def seal_run(run)
    start = @moof_at + int(run[:offset_at], 'l>')
    write(run[:offset_at], @moof_size + 8 + @payload.bytesize)
    run[:size_ats].each { start += seal_sample(start, it) }
  end

  def seal_sample(start, size_at)
    size = int(size_at, 'N')
    @payload << @seal.call(@segment.byteslice(start, size))
    write(size_at, size + 28)
    size
  end

  def int(at, format) = @moof.byteslice(at, 4).unpack1(format)

  def write(at, value) = @moof[at, 4] = [value].pack('N')

  def boxes(bytes, from, to)
    found = []
    while from + 8 <= to
      size, type = bytes.byteslice(from, 8).unpack('Na4')
      found << [type, from, size]
      from += size
    end
    found
  end

  def runs
    boxes(@moof, 8, @moof.bytesize).select { it.first == 'traf' }.map do |_, traf, size|
      run(boxes(@moof, traf + 8, traf + size).assoc('trun')[1])
    end
  end

  def run(trun)
    flags = @moof.byteslice(trun + 8, 4).unpack1('N') & 0xffffff
    raise 'a run without data offset or sample sizes' unless flags.allbits?(0x201)

    { offset_at: trun + 16, size_ats: size_ats(trun, flags) }
  end

  def size_ats(trun, flags)
    entry = [0x100, 0x200, 0x400, 0x800].count { flags.allbits?(it) } * 4
    first = trun + 20 + (flags.allbits?(0x4) ? 4 : 0) + (flags.allbits?(0x100) ? 4 : 0)
    Array.new(@moof.byteslice(trun + 12, 4).unpack1('N')) { first + (it * entry) }
  end
end
