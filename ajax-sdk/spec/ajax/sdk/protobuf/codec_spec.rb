# frozen_string_literal: true

# Expected bytes come from `protoc --encode` on spec/fixtures/protobuf/sample.proto.
RSpec.describe Ajax::Sdk::Protobuf::Codec do
  subject(:codec) { described_class.new(registry) }

  let(:registry) { Ajax::Sdk::Protobuf::Registry.from_descriptor_set(File.binread(fixture)) }
  let(:fixture) { File.join(__dir__, '../../../fixtures/protobuf/sample.pb') }
  let(:decode_error) { Ajax::Sdk::Protobuf::DecodeError }
  let(:scalars) do
    {
      a_double: 1.5, a_float: -2.25, a_int64: -3, a_uint64: 18_446_744_073_709_551_615, a_int32: -5, a_fixed64: 6,
      a_fixed32: 7, a_bool: true, a_string: 'héllo', a_bytes: "\x00\xFF".b, a_uint32: 4_294_967_295,
      a_level: :LEVEL_HIGH, a_sfixed32: -15, a_sfixed64: -16, a_sint32: -17, a_sint64: -18
    }
  end
  let(:scalars_hex) do
    '09000000000000f83f15000010c018fdffffffffffffffff0120ffffffffffffffffff0128fbffffffffffffffff0131060000000000' \
      '00003d0700000040014a0668c3a96c6c6f620200ff68ffffffff0f70027df1ffffff8101f0ffffffffffffff880121900123'
  end

  def hex(bytes) = bytes.unpack1('H*')
  def bytes(hex) = [hex].pack('H*')

  it 'encodes 150 as 08 96 01' do
    expect(hex(codec.encode('koti.sample.Sample', a: 150))).to eq('089601')
  end

  it 'round-trips scalars of every wire type', :aggregate_failures do
    expect(hex(codec.encode('koti.sample.Scalars', scalars))).to eq(scalars_hex)
    expect(codec.decode('koti.sample.Scalars', bytes(scalars_hex))).to eq(scalars)
  end

  it 'decodes a packed repeated int32' do
    expect(codec.decode('koti.sample.Sample', bytes('12040102ac02'))).to eq(numbers: [1, 2, 300])
  end

  it 'encodes a repeated int32 packed' do
    expect(hex(codec.encode('koti.sample.Sample', numbers: [1, 2, 300]))).to eq('12040102ac02')
  end

  it 'decodes a map field into a Hash' do
    decoded = codec.decode('koti.sample.Sample', bytes('1a050a017810011a050a01791002'))
    expect(decoded).to eq(counts: { 'x' => 1, 'y' => 2 })
  end

  it 'encodes repeated messages, a oneof member and an explicit zero' do
    expect(hex(codec.encode('koti.sample.Sample', items: [{ a_int32: 1 }, { a_int32: 2 }], name: 'n', maybe: 0)))
      .to eq('2a0228012a02280232016e4000')
  end

  it 'keeps an unknown enum value as its number' do
    expect(codec.decode('koti.sample.Sample', bytes('3805'))).to eq(level: 5)
  end

  it 'skips an unknown field' do
    expect(codec.decode('koti.sample.Sample', bytes('08019a06026869'))).to eq(a: 1)
  end

  it 'raises DecodeError when a length runs past the buffer' do
    expect { codec.decode('koti.sample.Sample', bytes('320a6e')) }.to raise_error(decode_error)
  end

  it 'raises DecodeError on a group wire type' do
    expect { codec.decode('koti.sample.Sample', bytes('0b')) }.to raise_error(decode_error, /wire type 3/)
  end

  it 'raises DecodeError on a varint longer than ten bytes' do
    expect { codec.decode('koti.sample.Sample', bytes("08#{'ff' * 10}01")) }.to raise_error(decode_error)
  end

  it 'rejects a field the schema does not have' do
    expect { codec.encode('koti.sample.Sample', nope: 1) }.to raise_error(ArgumentError, /nope/)
  end
end
