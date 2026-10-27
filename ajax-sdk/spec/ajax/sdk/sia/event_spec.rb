# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Sia::Event do
  def message(content)
    Ajax::Sdk::Sia::Message.new(type: 'SIA-DCS', encrypted: true, sequence: '0012', receiver: nil, line: 'L0',
                                account: 'AAA', content:, timestamp: nil)
  end

  it 'reads the group and the number that follow an Ajax hub disarming' do
    expect(described_class.from(message('#AAA|Nri1/OP501'))).to have_attributes(
      account: 'AAA', group: '1', code: 'OP', label: 'Opening Report', number: '501', text: ''
    )
  end

  it 'keeps a content it cannot read whole in text' do
    expect(described_class.from(message('#AAA|1401 01 001')))
      .to have_attributes(code: nil, number: nil, text: '#AAA|1401 01 001')
  end
end
