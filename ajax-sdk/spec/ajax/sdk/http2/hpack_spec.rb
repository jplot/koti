# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Http2::Hpack do
  def bytes(hex) = [hex].pack('H*')

  describe 'RFC 7541 Appendix C.3, requests without Huffman' do
    let(:decoder) { described_class::Decoder.new }

    it 'decodes the first request, filling the dynamic table' do
      headers = decoder.decode(bytes('828684410f7777772e6578616d706c652e636f6d'))

      expect(headers).to eq([%w[:method GET], %w[:scheme http], %w[:path /], [':authority', 'www.example.com']])
    end

    it 'decodes three requests, carrying the dynamic table across them', :aggregate_failures do
      decoder.decode(bytes('828684410f7777772e6578616d706c652e636f6d'))
      second = decoder.decode(bytes('828684be58086e6f2d6361636865'))
      third = decoder.decode(bytes('828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565'))

      expect(second).to eq([%w[:method GET], %w[:scheme http], %w[:path /],
                            [':authority', 'www.example.com'], ['cache-control', 'no-cache']])
      expect(third).to eq([%w[:method GET], %w[:scheme https], [':path', '/index.html'],
                           [':authority', 'www.example.com'], %w[custom-key custom-value]])
    end
  end

  describe 'RFC 7541 Appendix C.4, requests with Huffman' do
    it 'decodes the first request' do
      headers = described_class::Decoder.new.decode(bytes('828684418cf1e3c2e5f23a6ba0ab90f4ff'))

      expect(headers).to eq([%w[:method GET], %w[:scheme http], %w[:path /],
                             [':authority', 'www.example.com']])
    end
  end

  describe 'RFC 7541 Appendix C.6, responses with Huffman and eviction at 256 bytes' do
    it 'decodes the first response', :aggregate_failures do
      decoder = described_class::Decoder.new(max_size: 256)
      hex = '488264025885aec3771a4b6196d07abe941054d444a8200595040b816' \
            '6e082a62d1bff6e919d29ad171863c78f0b97c8e9ae82ae43d3'

      headers = decoder.decode(bytes(hex))

      expect(headers).to eq([[':status', '302'], %w[cache-control private],
                             ['date', 'Mon, 21 Oct 2013 20:13:21 GMT'], ['location', 'https://www.example.com']])
    end
  end

  describe 'the encoder' do
    it 'round-trips what it writes, indexing a static name' do
      headers = [%w[:method GET], ['custom', 'value'], ['user-agent', 'koti']]

      block = described_class::Encoder.new.encode(headers)

      expect(described_class::Decoder.new.decode(block)).to eq(headers)
    end
  end

  describe 'a malformed block' do
    it 'raises CompressionError on an index past the table' do
      expect { described_class::Decoder.new.decode([0xBF].pack('C')) }
        .to raise_error(Ajax::Sdk::Http2::CompressionError, /past the table/)
    end
  end
end
