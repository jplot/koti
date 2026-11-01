# frozen_string_literal: true

RSpec.describe Miele::Sdk do
  it 'needs appliances or a Miele account to listen to' do
    expect { described_class.events(hosts: [], cloud: nil) { nil } }.to raise_error(ArgumentError)
  end

  it 'follows the cloud only when given one', :aggregate_failures do
    allow(described_class).to receive(:cloud).and_return(instance_double(Miele::Sdk::Cloud::Channel))
    allow(Miele::Sdk::Events::Merge).to receive(:new).and_return(instance_double(Miele::Sdk::Events::Merge, each: nil))

    described_class.events(hosts: ['127.0.0.1']) { nil }

    expect(Miele::Sdk::Events::Merge).to have_received(:new).with([an_instance_of(Miele::Sdk::Events::Listener)])
  end
end
