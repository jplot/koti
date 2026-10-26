# frozen_string_literal: true

require 'stringio'

RSpec.describe Ajax::Sdk::Http2::Frame do
  it 'round-trips a frame through to_s and read' do
    frame = described_class.new(type: 1, flags: 4, stream_id: 7, payload: 'abc'.b)

    expect(described_class.read(StringIO.new(frame.to_s))).to eq(frame)
  end

  it 'reports a set flag' do
    frame = described_class.new(type: 0, flags: 0x5, stream_id: 1, payload: ''.b)

    expect(frame.flag?(0x4)).to be(true)
  end

  it 'raises EOFError on a truncated header' do
    expect { described_class.read(StringIO.new('123')) }.to raise_error(EOFError)
  end

  it 'raises EOFError on a truncated payload' do
    header = [0, 4, 0, 0, 1].pack('CnCCN')

    expect { described_class.read(StringIO.new(header)) }.to raise_error(EOFError)
  end
end
