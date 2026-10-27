# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Sia::Cipher do
  it 'decrypts what a hub encrypts with a 16-character key' do
    text = 'pppp|#AAA|Nri1/BA3]_09:30:15,10-27-2026'.ljust(48, ' ')

    expect(described_class.new(SiaFrames::KEY).decrypt(sia_encrypt(text))).to eq(text)
  end

  it 'decodes a key of 32 hexadecimal digits to its 16 bytes' do
    key = '000102030405060708090A0B0C0D0E0F'

    expect(described_class.new(key).decrypt(sia_encrypt('x' * 16, [key].pack('H*')))).to eq('x' * 16)
  end

  it 'pads with zeros on the left to whole blocks' do
    hex = described_class.new(SiaFrames::KEY).encrypt(']_09:30:15,10-27-2026')

    expect(sia_decrypt(hex)).to eq(']_09:30:15,10-27-2026'.rjust(32, '0'))
  end

  it 'never prints the key in inspect' do
    expect(described_class.new(SiaFrames::KEY).inspect).not_to include(SiaFrames::KEY)
  end

  it 'refuses a key that is neither 16 characters nor 32 hexadecimal digits', :aggregate_failures do
    ['short', 'x' * 24, 'x' * 32].each do |key|
      expect { described_class.new(key) }.to raise_error(Ajax::Sdk::ConfigurationError)
    end
  end
end
