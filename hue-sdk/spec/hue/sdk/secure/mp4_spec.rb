# frozen_string_literal: true

require 'open3'
require 'timeout'

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

  it 'rewrites every sample of a two-track file with what the block gives, moving every chunk' do
    clip = File.binread(File.join(media, 'clip.mp4'))
    expect(SegmentReader.file_samples(described_class.file(clip) { "#{it}tail" }))
      .to eq(SegmentReader.file_samples(clip).map { |track, data, *rest| [track, "#{data}tail", *rest] })
  end

  it 'drops a file whose samples it could not replace, and its open files with it', :aggregate_failures do
    failing = -> { described_class.file(File.binread(File.join(media, 'clip.mp4'))) { raise Hue::Sdk::Secure::E2eeError } }
    files = Dir.children('/dev/fd').size
    5.times { expect(&failing).to raise_error(Hue::Sdk::Secure::E2eeError) }
    expect(Dir.children('/dev/fd').size).to eq(files)
  end

  it 'drops a file a timeout interrupts, and its open files with it', :aggregate_failures do
    clip = File.binread(File.join(media, 'clip.mp4'))
    files = Dir.children('/dev/fd').size
    5.times { expect { Timeout.timeout(0.05) { described_class.file(clip) { sleep 1 } } }.to raise_error(Timeout::Error) }
    expect(Dir.children('/dev/fd').size).to eq(files)
  end

  it 'refuses a file GPAC cannot read' do
    expect { described_class.file('not an MP4 file') { it } }.to raise_error(Hue::Sdk::Secure::E2eeError, /GPAC/)
  end
end
