# frozen_string_literal: true

RSpec.describe Ajax::Sdk::Sia::Codes do
  it 'labels the codes an Ajax hub sends' do
    expect(%w[BA XT XR XL XC TA TR CL OP NL YS].map { described_class.label(it) }).to all(be_a(String))
  end

  it 'has no label for an unknown code' do
    expect(described_class.label('QQ')).to be_nil
  end
end
