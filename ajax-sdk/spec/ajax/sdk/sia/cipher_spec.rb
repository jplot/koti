# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Sia::Cipher do
  it 'decrypts what a hub encrypts with a 16-character key' do
    text = 'pppp|#AAA|Nri1/BA3]_09:30:15,10-27-2026'.ljust(48, ' ')

    expect(described_class.new(SiaFrames::KEY).decrypt(sia_encrypt(text))).to eq(text)
  end

  it 'uses AES-256 for a 32-character key' do
    key = '0123456789ABCDEF0123456789ABCDEF'

    expect(described_class.new(key).decrypt(sia_encrypt('x' * 16, key))).to eq('x' * 16)
  end

  it 'pads with zeros on the left to whole blocks' do
    hex = described_class.new(SiaFrames::KEY).encrypt(']_09:30:15,10-27-2026')

    expect(sia_decrypt(hex)).to eq(']_09:30:15,10-27-2026'.rjust(32, '0'))
  end

  it 'never prints the key in inspect' do
    expect(described_class.new(SiaFrames::KEY).inspect).not_to include(SiaFrames::KEY)
  end

  it 'refuses a key that is not 16, 24 or 32 characters' do
    expect { described_class.new('short') }.to raise_error(Ajax::Sdk::ConfigurationError)
  end
end
