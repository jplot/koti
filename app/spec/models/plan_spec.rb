# frozen_string_literal: true

RSpec.describe Plan do
  it 'refuses a document that is not a koti plan' do
    plan = described_class.new(document: { 'format' => 'x' })
    expect(plan.valid?).to be(false)
  end

  it 'puts the problems on the document' do
    plan = described_class.new(document: { 'format' => 'x' })
    plan.validate
    expect(plan.errors[:document]).to include(a_string_including('`/format`'))
  end
end
