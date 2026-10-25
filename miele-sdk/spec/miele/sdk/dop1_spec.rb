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

  it 'builds the setting requests' do
    expect([described_class.setting(40_010), described_class.write_setting(40_010, 3)])
      .to eq(%w[12010100009C4A 12010200009C4A00000003])
  end

  it 'rejects a setting value wider than 32 bits' do
    expect { described_class.write_setting(40_010, 1 << 32) }.to raise_error(ArgumentError)
  end

  it 'reads a setting value after its echoed id' do
    expect(described_class.setting_value('12011100009C4A000000030000000000000005', 40_010)).to eq(3)
  end

  it 'finds no value in a response without the echoed id' do
    expect(described_class.setting_value('120111020002', 40_010)).to be_nil
  end
end
