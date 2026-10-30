# frozen_string_literal: true

RSpec.describe Miele::Sdk::Dop1 do
  it 'builds the fan level request' do
    expect(described_class.fan_level(2)).to eq('8E01020000FF0200')
  end

  it 'rejects a fan level above 5' do
    expect { described_class.fan_level(6) }.to raise_error(ArgumentError, /0 to 5/)
  end

  it 'builds the run-on time request' do
    expect(described_class.fan_run_on_time(15)).to eq('8E060200000F')
  end

  it 'rejects a run-on time of 10 minutes' do
    expect { described_class.fan_run_on_time(10) }.to raise_error(ArgumentError, /0, 5 or 15/)
  end

  it 'builds the main light request' do
    expect([described_class.main_light(true), described_class.main_light(false)])
      .to eq(%w[14000200020104000000000000FFFF0000 1400020002010000000000000000000000])
  end

  it 'reads a setting with structure version 1' do
    expect(described_class.setting(40_012)).to eq('12010100019C4C')
  end

  it 'writes a setting with structure version 1' do
    expect(described_class.write_setting(40_012, 1)).to eq('12010200019C4C00000001')
  end

  it 'rejects a setting value wider than 32 bits' do
    expect { described_class.write_setting(40_010, 1 << 32) }.to raise_error(ArgumentError)
  end

  it 'reads the value at its fixed place in the answer' do
    expect(described_class.setting_value('12011100 019C4C 00000005 00000000 000000FF'.delete(' '))).to eq(5)
  end

  it 'finds no value in an answer too short to hold one' do
    expect(described_class.setting_value('120111020002')).to be_nil
  end
end
