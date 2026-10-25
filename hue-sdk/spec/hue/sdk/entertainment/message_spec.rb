# frozen_string_literal: true

require 'hue/sdk/entertainment/message'

RSpec.describe Hue::Sdk::Entertainment::Message do
  let(:id) { '1a8d99cc-967b-44f2-9202-43f976c0fa6b' }

  def encode(**) = described_class.encode(configuration_id: id, sequence: 7, channels: { 0 => [1.0, 0.0, 0.5] }, **)

  it 'encodes an RGB message' do
    expected = 'HueStream'.b + "\x02\x00\x07\x00\x00\x00\x00".b + id.b + "\x00\xFF\xFF\x00\x00\x80\x00".b
    expect(encode).to eq(expected)
  end

  it 'flags the XY and brightness color space' do
    expect(encode(color_space: :xy).getbyte(14)).to eq(1)
  end

  it 'wraps the sequence at 256' do
    expect(encode(sequence: 263).getbyte(11)).to eq(7)
  end

  it 'clamps values outside 0..1' do
    expect(encode(channels: { 3 => [1.2, -0.1, 1.0] }).byteslice(52, 7)).to eq("\x03\xFF\xFF\x00\x00\xFF\xFF".b)
  end

  it 'rejects more than 20 channels' do
    expect { encode(channels: 21.times.to_h { [it, [0.0, 0.0, 0.0]] }) }.to raise_error(ArgumentError, /at most 20/)
  end

  it 'rejects a configuration id that is not 36 characters long' do
    expect { encode(configuration_id: 'abc') }.to raise_error(ArgumentError, /36/)
  end

  it 'rejects an unknown color space' do
    expect { encode(color_space: :hsv) }.to raise_error(ArgumentError, /:rgb or :xy/)
  end
end
