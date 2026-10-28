# frozen_string_literal: true

require 'open3'

RSpec.describe Ajax::Sdk::Sia::Codes do
  it 'labels the codes an Ajax hub sends' do
    expect(%w[BA XT XR XL XC TA TR CL OP NL YS].map { described_class.label(it) }).to all(be_a(String))
  end

  it 'reads its labels as UTF-8 whatever the locale, as under launchd' do
    script = "label = Ajax::Sdk::Sia::Codes.label('AA'); print label.encoding, ' ', label.valid_encoding?"
    output, = Open3.capture2({ 'LC_ALL' => 'C' }, RbConfig.ruby, '-r./lib/ajax/sdk/sia/codes', '-e', script)
    expect(output).to eq('UTF-8 true')
  end

  it 'has no label for an unknown code' do
    expect(described_class.label('QQ')).to be_nil
  end
end
