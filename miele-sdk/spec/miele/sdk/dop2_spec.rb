# frozen_string_literal: true

RSpec.describe Miele::Sdk::Dop2 do
  let(:field) { described_class::Field }

  def tlv(index, type, value) = [index, type].pack('nC') + value.b

  def leaf_bytes(*fields)
    body = [2, 1585, 0, 0, fields.size].pack('n5') + fields.join
    [body.bytesize].pack('n') + body
  end

  def struct(*fields) = [fields.size].pack('n') + fields.join

  def decode_one(code, payload) = described_class.decode(leaf_bytes(tlv(1, code, payload))).fields[1]

  def scalars = %i[bool u8 i8 e8 u16 i16 e16 u32 i32 e32 u64 i64 e64 float double]

  def sample(type)
    { bool: true, u8: 255, i8: -2, e8: 3, u16: 513, i16: -5, e16: 7, u32: 70_000, i32: -7, e32: 9,
      u64: 2**40, i64: -(2**40), e64: 11, float: 1.5, double: 2.25 }.fetch(type)
  end

  def wire(type, value)
    directive = { bool: 'C', u8: 'C', i8: 'c', e8: 'C', u16: 'n', i16: 's>', e16: 'n', u32: 'N', i32: 'l>',
                  e32: 'N', u64: 'Q>', i64: 'q>', e64: 'Q>', float: 'g', double: 'G' }.fetch(type)
    [value == true ? 1 : value].pack(directive)
  end

  def leaf(fields) = described_class::Leaf.new(unit: 2, attribute: 1585, idx1: 0, idx2: 0, fields:)

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

  it 'decodes every type code the app knows', :aggregate_failures do
    scalars.each.with_index(1) do |type, code|
      expect(decode_one(code, wire(type, sample(type)))).to eq(field[type, sample(type)])
      expect(decode_one(code + 16, [2].pack('n') + (wire(type, sample(type)) * 2)))
        .to eq(field[:"#{type}_array", [sample(type)] * 2])
    end
  end

  it 'reads a string without its trailing NULs' do
    expect(decode_one(0x20, "\x00\x07Pizza\0\0")).to eq(field[:string, 'Pizza'])
  end

  it 'writes a string with one trailing NUL counted in its length' do
    expect(described_class.encode(leaf(1 => field[:string, 'Pizza'])))
      .to eq(leaf_bytes(tlv(1, 0x20, "\x00\x06Pizza\x00")))
  end

  it 'encodes the program selection the oven sends' do
    selection = described_class::Leaf.new(
      unit: 2, attribute: 1577, idx1: 0, idx2: 0,
      fields: { 1 => field[:e16, 13], 3 => field[:e8, 2], 2 => field[:u16, 6],
                7 => field[:struct, { 6 => field[:u16, 18_000] }] }
    )
    expect(described_class.encode(selection).unpack1('H*'))
      .to eq('002200020629000000000004 000107000d 00030402 0002050006 0007100001 0006054650'.delete(' '))
  end

  it 'round-trips arrays and struct arrays' do
    arrays = leaf(1 => field[:u16_array, [1, 600]], 2 => field[:e16_array, [1, 2]],
                  3 => field[:struct_array, [{ 1 => field[:e8, 3] }, { 2 => field[:u16, 5] }]])
    expect(described_class.decode(described_class.encode(arrays))).to eq(arrays)
  end

  it 'refuses an array element out of range' do
    expect { described_class.encode(leaf(1 => field[:u8_array, [1, 300]])) }
      .to raise_error(ArgumentError, /300 does not fit a u8 field/)
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

  it 'stops at the declared length instead of reading the padding' do
    bytes = leaf_bytes(tlv(1, 0x08, [70_000].pack('N')))
    cut = [bytes.unpack1('n') - 2].pack('n') + bytes.byteslice(2..-3)
    expect { described_class.decode("#{cut}    ") }.to raise_error(described_class::DecodeError, /truncated/)
  end

  it 'encodes the scalar fields it decodes' do
    leaf = described_class::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                                     fields: { 1 => field[:e8, 4], 2 => field[:i32, -7], 3 => field[:bool, false] })
    expect(described_class.decode(described_class.encode(leaf))).to eq(leaf)
  end

  it 'refuses a value outside the range of its field', :aggregate_failures do
    [field[:u8, 300], field[:i8, -129]].each do |wide|
      leaf = described_class::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0, fields: { 1 => wide })
      expect { described_class.encode(leaf) }.to raise_error(ArgumentError, /does not fit/)
    end
  end
end
