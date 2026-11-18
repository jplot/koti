# frozen_string_literal: true

RSpec.describe User do
  it 'normalizes the address' do
    user = described_class.create!(email_address: ' Ana@Example.TEST ', password: 'correct horse')
    expect(user.email_address).to eq('ana@example.test')
  end
end
