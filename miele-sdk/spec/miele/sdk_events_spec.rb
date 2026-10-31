# frozen_string_literal: true

RSpec.describe Miele::Sdk do
  it 'needs appliances or a Miele account to listen to' do
    expect { described_class.events(hosts: [], cloud: nil) { nil } }.to raise_error(ArgumentError)
  end
end
