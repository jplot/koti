# frozen_string_literal: true

RSpec.describe Miele::Sdk::Dop2 do
  let(:field) { described_class::Field }

  def tlv(index, type, value) = [index, type].pack('nC') + value.b

  def leaf_bytes(*fields)
    body = [2, 1585, 0, 0, fields.size].pack('n5') + fields.join
    [body.bytesize].pack('n') + body
  end

  def struct(*fields) = [fields.size].pack('n') + fields.join

  it 'decodes scalar, struct, array and string fields' do
    bytes = leaf_bytes(tlv(1, 0x01, "\x01"), tlv(2, 0x06, [-5].pack('s>')),
                       tlv(3, 0x10, struct(tlv(1, 0x08, [70_000].pack('N')))), tlv(4, 0x17, [2, 1, 2].pack('n3')),
                       tlv(5, 0x20, "\x00\x05H7164"), tlv(6, 0x21, "\x00\x02#{struct(tlv(1, 0x04, "\x03")) * 2}"))
    expect(described_class.decode("#{bytes}   ").fields).to eq(
      1 => field[:bool, true], 2 => field[:i16, -5], 3 => field[:struct, { 1 => field[:u32, 70_000] }],
      4 => field[:e16_array, [1, 2]], 5 => field[:string, 'H7164'],
      6 => field[:struct_array, [{ 1 => field[:e8, 3] }, { 1 => field[:e8, 3] }]]
    )
  end

  it 'reads the header of a leaf' do
    expect(described_class.decode(leaf_bytes)).to have_attributes(unit: 2, attribute: 1585, idx1: 0, idx2: 0)
  end

  it 'raises DecodeError on an unknown type' do
    expect { described_class.decode(leaf_bytes(tlv(1, 0x42, ''))) }
      .to raise_error(described_class::DecodeError, 'unknown DOP2 type 0x42 at byte 14')
  end

  it 'raises DecodeError on a truncated leaf' do
    expect { described_class.decode(leaf_bytes(tlv(1, 0x08, "\x00"))) }
      .to raise_error(described_class::DecodeError, /truncated/)
  end

  it 'encodes the scalar fields it decodes' do
    leaf = described_class::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                                     fields: { 1 => field[:e8, 4], 2 => field[:i32, -7], 3 => field[:bool, false] })
    expect(described_class.decode(described_class.encode(leaf))).to eq(leaf)
  end

  it 'refuses to encode a composite field' do
    leaf = described_class::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0, fields: { 1 => field[:string, 'x'] })
    expect { described_class.encode(leaf) }.to raise_error(ArgumentError, /string/)
  end
end
