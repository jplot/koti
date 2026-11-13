# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Mp4 do
  let(:media) { File.expand_path('../../../fixtures/media', __dir__) }
  let(:init) { File.binread(File.join(media, 'init.mp4')) }
  let(:segment) { File.binread(File.join(media, 'segment1.m4s')) }

  it 'rewrites every sample of a segment with what the block gives, and nothing else', :aggregate_failures do
    rewritten = described_class.segment(segment, init:) { "#{it}tail" }
    expect(SegmentReader.samples(rewritten, init:))
      .to eq(SegmentReader.samples(segment, init:).map { |track, data, *rest| [track, "#{data}tail", *rest] })
    expect(SegmentReader.header(rewritten)).to eq(SegmentReader.header(segment))
  end

  it 'refuses a segment GPAC cannot read' do
    expect { described_class.segment(segment.byteslice(0, 600), init:) { it } }
      .to raise_error(Hue::Sdk::Secure::E2eeError, /GPAC/)
  end
end
