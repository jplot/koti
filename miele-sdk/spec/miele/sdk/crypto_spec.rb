# frozen_string_literal: true

RSpec.describe Miele::Sdk::Crypto do
  let(:key) { (0..63).to_a.pack('C*') }
  let(:group_id) { ['0123456789ABCDEF'].pack('H*') }
  let(:date) { 'Sun, 25 Oct 2026 12:00:00 GMT' }
  let(:accept) { 'application/vnd.miele.v1+json' }

  def hex(bytes) = bytes.unpack1('H*').upcase

  def request(method, path, content_type: '', body: '')
    described_class.signature(key:, lines: [method, "192.0.2.20#{path}", content_type, accept, date], body:)
  end

  it 'signs a GET like the reference implementation' do
    expect(described_class.authorization(group_id:, signature: request('GET', '/Devices/')))
      .to eq('MieleH256 0123456789ABCDEF:8EADDBE00B336296B6722F1A63741151CCAFB29F07AD3D062DFDBF8882C4DA84')
  end

  it 'pads a short JSON body to 64 bytes before its closing brace' do
    expect(described_class.pad('{"Light":1}')).to eq("{\"Light\":1#{' ' * 53}}")
  end

  it 'pads a binary body with spaces to a 16-byte multiple' do
    expect(described_class.pad("\x00\x01\x02".b)).to eq("\x00\x01\x02#{' ' * 13}".b)
  end

  it 'signs and encrypts a PUT like the reference implementation', :aggregate_failures do
    body = described_class.pad('{"Light":1}')
    signature = request('PUT', '/Devices/000123456789/State',
                        content_type: 'application / vnd.miele.v1 + json; charset = utf - 8', body:)
    expect(hex(signature)).to eq('CDB259BE53F3B86C145329C8BCFB9188B158F9A72FDA3181C515B3492AABC45F')
    expect(hex(described_class.encrypt(key:, signature:, plaintext: body))).to eq(
      '830E43DC7D448FF733DECD927E7CEEBFCC54257138D450299543B6B53CE52AEB' \
      'A35B6662E90B61955FC5DABB0DD81240BE178EE10172B487981B923BB6E46088'
    )
  end

  it 'authenticates and decrypts a response like the reference implementation', :aggregate_failures do
    plaintext = described_class.pad('{"Status":1}')
    lines = [200, 'application/vnd.miele.v1+json; charset=utf-8', date]
    signature = described_class.signature(key:, lines:, body: plaintext)
    ciphertext = ['4196018687664f7b70ce53d7ee24303d0bfbfa7ec5beb156898ed63f8e9238d9' \
                  'b971b3c45eb30c8a445f92872be9c1f547ef67c6656f8b3eff5c662362f03ede'].pack('H*')
    expect(hex(signature)).to eq('80B2BBB584E52E5A4022B6DFAA398A306EAC50A0784C4DB4DB7CBD99ED11C4FE')
    expect(described_class.decrypt(key:, signature:, ciphertext:)).to eq(plaintext)
  end
end
