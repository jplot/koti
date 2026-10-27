# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Sia::Message do
  let(:clear) { "\n43580023\"SIA-DCS\"0084L0#AAA[#AAA|Nri1/XC12]\r" }
  let(:cipher) { Ajax::Sdk::Sia::Cipher.new(SiaFrames::KEY) }

  it 'computes the CRC-16/ARC check value' do
    expect(Ajax::Sdk::Sia.crc('123456789')).to eq(0xBB3D)
  end

  it 'parses a clear SIA-DCS frame' do
    expect(described_class.parse(clear)).to have_attributes(
      type: 'SIA-DCS', encrypted: false, sequence: '0084', receiver: nil, line: 'L0', account: 'AAA',
      content: '#AAA|Nri1/XC12', timestamp: nil
    )
  end

  it 'rejects a frame whose CRC is wrong' do
    expect { described_class.parse(clear.sub('4358', '4359')) }.to raise_error(Ajax::Sdk::Sia::FrameError, /CRC/)
  end

  it 'rejects a frame whose length is wrong' do
    expect { described_class.parse(clear.sub('0023', '0024')) }.to raise_error(Ajax::Sdk::Sia::FrameError, /length/)
  end

  it 'rejects bytes that are not a DC-09 frame' do
    expect { described_class.parse("\nnoise\r") }.to raise_error(Ajax::Sdk::Sia::FrameError)
  end

  it 'decrypts an encrypted frame and reads its timestamp' do
    time = Time.utc(2026, 10, 27, 9, 30, 15)

    message = described_class.parse(encrypted_sia_frame('SIA-DCS', '#AAA|Nri1/BA3', time:), cipher:)

    expect(message).to have_attributes(encrypted: true, receiver: 'R0', content: '#AAA|Nri1/BA3', timestamp: time)
  end

  it 'reads only the header of an encrypted frame when no cipher is given' do
    message = described_class.parse(encrypted_sia_frame('SIA-DCS', '#AAA|Nri1/BA3'))

    expect(message).to have_attributes(encrypted: true, account: 'AAA', content: nil)
  end

  it 'rejects an encrypted frame the key does not open' do
    frame = encrypted_sia_frame('SIA-DCS', '#AAA|Nri1/BA3', key: 'FEDCBA9876543210')

    expect { described_class.parse(frame, cipher:) }.to raise_error(Ajax::Sdk::Sia::FrameError)
  end

  it 'rejects an encrypted data frame without the pipe that ends its padding' do
    frame = sia_frame(%("*SIA-DCS"0001R0L0#AAA[#{sia_encrypt("]#{sia_stamp}".rjust(32, '0'))}))

    expect { described_class.parse(frame, cipher:) }.to raise_error(Ajax::Sdk::Sia::FrameError)
  end

  it 'reads an encrypted link test without that pipe' do
    frame = sia_frame(%("*NULL"0001R0L0#AAA[#{sia_encrypt("]#{sia_stamp}".rjust(32, '0'))}))

    expect(described_class.parse(frame, cipher:)).to have_attributes(type: 'NULL', content: '')
  end

  it 'answers a clear frame with a clear ACK' do
    expect(described_class.parse(clear).ack).to eq(sia_frame('"ACK"0084L0#AAA[]'))
  end

  it 'answers an encrypted frame with an encrypted ACK carrying the time' do
    message = described_class.parse(encrypted_sia_frame('SIA-DCS', '#AAA|Nri1/BA3', sequence: '0042'), cipher:)

    hex = message.ack(cipher:)[/\A\n\h{8}"\*ACK"0042R0L0#AAA\[(\h+)\r\z/, 1]

    expect(sia_decrypt(hex.to_s)).to match(/\A0+\]_\d\d:\d\d:\d\d,\d\d-\d\d-\d{4}\z/)
  end

  it 'answers DUH in clear' do
    expect(described_class.parse(clear).duh).to eq(sia_frame('"DUH"0084L0#AAA[]'))
  end

  it 'leaves the time it stamps in its own zone' do
    time = Time.new(2026, 10, 27, 1, 34, 8, '+01:00')

    described_class.nak(time)

    expect(time.utc_offset).to eq(3600)
  end

  it 'builds a NAK with the current timestamp' do
    time = Time.utc(2026, 10, 27, 9, 30, 15)

    expect(described_class.nak(time)).to eq(sia_frame('"NAK"0000R0L0A0[]_09:30:15,10-27-2026'))
  end
end
