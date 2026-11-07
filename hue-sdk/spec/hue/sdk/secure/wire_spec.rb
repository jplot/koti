# frozen_string_literal: true

RSpec.describe Hue::Sdk::Secure::Wire do
  it 'decodes each wire type by tag' do
    bytes = "\x08\x96\x01".b + "\x11#{"\x01" * 8}".b + "\x1a\x03abc".b + "\x25#{"\x02" * 4}".b
    expect(described_class.decode(bytes)).to eq(1 => [150], 2 => ["\x01".b * 8], 3 => ['abc'.b], 4 => ["\x02".b * 4])
  end

  it 'keeps a repeated field in order' do
    expect(described_class.decode(FakeHomes.message(9 => %w[a b c]))).to eq(9 => %w[a b c].map(&:b))
  end

  it 'raises on a wire type protobuf 3 does not use' do
    expect { described_class.decode("\x0b".b) }.to raise_error(Hue::Sdk::Error, /wire type 3/)
  end

  it 'raises on a truncated message' do
    expect { described_class.decode("\x1a\x05ab".b) }.to raise_error(Hue::Sdk::Error, /truncated/)
  end

  it 'gives the defaults of protobuf 3 for an absent field', :aggregate_failures do
    expect([described_class.text({}, 1), described_class.number({}, 1), described_class.texts({}, 1)])
      .to eq(['', 0, []])
  end
end
