# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../schema/extract/assembly_store'

RSpec.describe Schema::Extract::AssemblyStore do
  let(:directory) { Dir.mktmpdir }
  let(:store) do
    entries = [['A.dll', 'MZplain'], ['fr/B.resources.dll', "XALZ\x00\x00\x00\x00#{[9].pack('V')}\x32abc\x03\x00".b],
               ['C.dll', "XALZ\x00\x00\x00\x00#{[36].pack('V')}\xFF\x010123456789abcdef\x10\x00\x01".b],
               ['D.dll', "XALZ\x00\x00\x00\x00#{[271].pack('V')}\xF0\xFF\x01#{'y' * 271}".b]]
    names = entries.map { |name, _| [name.bytesize].pack('V') + name }.join
    data_offset = 20 + 8 + (28 * entries.size) + names.bytesize
    descriptors = entries.each_with_index.map do |(_, data), index|
      [0, data_offset + entries.first(index).sum { it[1].bytesize }, data.bytesize].pack('V3') + ("\0" * 16)
    end
    "\x7FELF-junk".b + ['XABA', 0x80010002, entries.size, 1, 8].pack('a4V4') + ("\0" * 8) + descriptors.join +
      names + entries.map(&:last).join
  end

  after { FileUtils.remove_entry(directory) }

  it 'writes each assembly of the store under its name, decompressing LZ4 entries', :aggregate_failures do
    described_class.unpack(store, directory)
    expect(File.binread(File.join(directory, 'A.dll'))).to eq('MZplain')
    expect(File.binread(File.join(directory, 'fr/B.resources.dll'))).to eq('abcabcabc')
  end

  it 'reads the lengths of 15 and more that go on in the next bytes', :aggregate_failures do
    described_class.unpack(store, directory)
    expect(File.binread(File.join(directory, 'C.dll'))).to eq("#{'0123456789abcdef' * 2}0123")
    expect(File.binread(File.join(directory, 'D.dll'))).to eq('y' * 271)
  end

  it 'refuses a store of another version' do
    expect { described_class.unpack(store.sub([0x80010002].pack('V'), [0x80010003].pack('V')), directory) }
      .to raise_error(ArgumentError, /version 3/)
  end
end
