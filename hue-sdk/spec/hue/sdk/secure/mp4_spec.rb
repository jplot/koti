# frozen_string_literal: true

require 'open3'

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

  def rewrite_in_child(home)
    script = "require 'hue/sdk/secure'; init, segment = ARGV.map { File.binread(it) }; " \
             'Hue::Sdk::Secure::Mp4.segment(segment, init:) { it }'
    lib = File.expand_path('../../../../lib', __dir__)
    Open3.capture2e({ 'HOME' => home }, RbConfig.ruby, '-I', lib, '-e', script, File.join(media, 'init.mp4'),
                    File.join(media, 'segment1.m4s'))
  end

  it 'rewrites under a home it cannot write to, and writes nothing there' do
    Dir.mktmpdir do |home|
      File.chmod(0o555, home)
      output, status = rewrite_in_child(home)
      expect([status.exitstatus, Dir.children(home)]).to eq([0, []]), output
    ensure
      File.chmod(0o755, home)
    end
  end

  it 'keeps the segment type of the input, rather than flag every segment as the last' do
    rewritten = described_class.segment(segment, init:) { it }
    expect(rewritten.byteslice(0, rewritten.unpack1('N'))).to eq(segment.byteslice(0, segment.unpack1('N')))
  end

  it 'refuses a segment GPAC cannot read' do
    expect { described_class.segment(segment.byteslice(0, 600), init:) { it } }
      .to raise_error(Hue::Sdk::Secure::E2eeError, /GPAC/)
  end
end
