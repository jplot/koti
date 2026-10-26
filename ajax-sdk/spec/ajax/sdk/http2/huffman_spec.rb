# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Http2::Huffman do
  it 'round-trips arbitrary header strings' do
    ['www.example.com', 'no-cache', 'custom-value', '/index.html', 'Mon, 21 Oct 2013 20:13:21 GMT'].each do |text|
      expect(described_class.decode(described_class.encode(text))).to eq(text)
    end
  end

  it 'encodes www.example.com to the RFC 7541 C.4.1 string' do
    expect(described_class.encode('www.example.com').unpack1('H*')).to eq('f1e3c2e5f23a6ba0ab90f4ff')
  end

  it 'raises CompressionError when the EOS symbol appears in the stream' do
    expect { described_class.decode([0xFF, 0xFF, 0xFF, 0xFF].pack('C*')) }
      .to raise_error(Ajax::Sdk::Http2::CompressionError, /EOS/)
  end

  it 'raises CompressionError on padding that is not the EOS prefix' do
    expect { described_class.decode("\x00".b) }
      .to raise_error(Ajax::Sdk::Http2::CompressionError, /padding/)
  end
end
