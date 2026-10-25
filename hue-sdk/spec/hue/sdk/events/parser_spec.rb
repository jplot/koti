# frozen_string_literal: true

RSpec.describe Hue::Sdk::Events::Parser do
  subject(:parser) { described_class.new }

  def messages(*chunks) = chunks.each_with_object([]) { |chunk, found| parser.feed(chunk) { found << it } }

  it 'handles split chunks and comments' do
    expect(messages(": hi\n\nid: 1:0\nda", "ta: []\n\n")).to eq([{ id: '1:0', data: '[]' }])
  end

  it 'handles CRLF line endings' do
    expect(messages("id: 1:0\r\ndata: []\r\n\r\n")).to eq([{ id: '1:0', data: '[]' }])
  end

  it 'keeps a multibyte character split across chunks' do
    bytes = "id: 1:0\ndata: \"Salle à manger\"\n\n".b
    cut = bytes.index("\xC3".b) + 1
    expect(messages(bytes[0...cut], bytes[cut..])).to eq([{ id: '1:0', data: '"Salle à manger"' }])
  end
end
