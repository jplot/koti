# frozen_string_literal: true

RSpec.describe Miele::Sdk, :live do
  let(:appliances) { ENV.fetch('MIELE_HOSTS').split(',').map { described_class.appliance(it) } }

  before do
    missing = %w[MIELE_GROUP_ID MIELE_GROUP_KEY MIELE_HOSTS].reject { ENV.key?(it) }
    skip "set #{missing.join(', ')}" unless missing.empty?
    described_class.configure do |config|
      config.group_id = ENV.fetch('MIELE_GROUP_ID')
      config.group_key = ENV.fetch('MIELE_GROUP_KEY')
    end
    allow(Miele::Sdk::Connection).to receive(:request).and_wrap_original do |original, host, verb, *rest, **options|
      raise "live specs are read-only: #{verb.upcase} refused" unless verb == :get

      original.call(host, verb, *rest, **options)
    end
  end

  it 'discovers the configured appliances' do
    expect(described_class.discover.map(&:host)).to include(*ENV.fetch('MIELE_HOSTS').split(','))
  end

  it 'reads ident and state of each appliance', :aggregate_failures do
    appliances.each do |appliance|
      expect(appliance.device_type).not_to eq(:unknown)
      expect(appliance.state.status).not_to eq(:unknown)
    end
  end

  it 'gets a NotFoundError for a dop2 leaf from appliances that serve no DOP2', :aggregate_failures do
    appliances.reject { it.get("/Devices/#{it.fab}/").key?('DOP2') }.each do |appliance|
      expect { appliance.dop2(2, 1586) }.to raise_error(Miele::Sdk::NotFoundError)
    end
  end

  it 'cannot write' do
    expect { appliances.first.light_on }.to raise_error(RuntimeError, /read-only: PUT refused/)
  end
end
