# frozen_string_literal: true

# Seals each sample of an MP4 file in place, as a camera writes it, rather than through GPAC, which the gem reads it
# with. The samples grow by 28 bytes, and each chunk moves by 28 bytes for every sample stored before it.
class Mp4Sealer
  def initialize(mp4, &seal)
    @mp4 = mp4.b
    @seal = seal
    @mdat_at, @mdat_size = boxes(0, @mp4.bytesize).assoc('mdat').drop(1)
    @payload = ''.b
  end

  def sealed
    from = chunks.sort_by { it[:offset] }.reduce(@mdat_at + 8) { |at, chunk| seal_chunk(at, chunk) }
    @payload << @mp4.byteslice(from, mdat_end - from)
    "#{@mp4.byteslice(0, @mdat_at)}#{[@payload.bytesize + 8].pack('N')}mdat#{@payload}#{@mp4.byteslice(mdat_end..)}"
  end

  private

  def mdat_end = @mdat_at + @mdat_size

  def seal_chunk(from, chunk)
    @payload << @mp4.byteslice(from, chunk[:offset] - from)
    write(chunk[:offset_at], @mdat_at + 8 + @payload.bytesize)
    chunk[:sizes].reduce(chunk[:offset]) { |at, size_at| at + seal_sample(at, size_at) }
  end

  def seal_sample(at, size_at)
    size = int(size_at)
    @payload << @seal.call(@mp4.byteslice(at, size))
    write(size_at, size + 28)
    size
  end

  def chunks
    traks = children(boxes(0, @mp4.bytesize).assoc('moov')).select { it.first == 'trak' }
    traks.flat_map { |trak| track_chunks(%w[mdia minf stbl].reduce(trak) { |box, type| children(box).assoc(type) }) }
  end

  def track_chunks(stbl)
    stsz, stco, stsc = %w[stsz stco stsc].map { children(stbl).assoc(it)[1] }
    sizes = sample_sizes(stsz)
    entries(stco + 12).each_with_index.map do |offset_at, index|
      { offset_at:, offset: int(offset_at), sizes: Array.new(per_chunk(stsc, index + 1)) { sizes.next } }
    end
  end

  def sample_sizes(stsz)
    raise 'a fixed sample size' unless int(stsz + 12).zero?

    entries(stsz + 16).each
  end

  def per_chunk(stsc, chunk) = int(entries(stsc + 12, 12).select { int(it) <= chunk }.last + 4)

  def entries(count_at, width = 4) = Array.new(int(count_at)) { count_at + 4 + (width * it) }

  def int(at) = @mp4.byteslice(at, 4).unpack1('N')

  def write(at, value) = @mp4[at, 4] = [value].pack('N')

  def children(box) = boxes(box[1] + 8, box[1] + box[2])

  def boxes(from, to)
    found = []
    while from + 8 <= to
      size, type = @mp4.byteslice(from, 8).unpack('Na4')
      found << [type, from, size]
      from += size
    end
    found
  end
end
