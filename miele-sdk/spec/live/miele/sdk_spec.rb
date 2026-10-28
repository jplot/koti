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

  def unknown_keys(type, data, path)
    own = type.extension_member ? [] : (data.keys - type.json_keys.values).map { "#{path} has #{it}" }
    own + type.nested_members.flat_map do |member, nested_type|
      key = type.json_keys.fetch(member)
      data[key] ? mismatches(nested_type, data[key], "#{path}.#{key}") : []
    end
  end

  def mismatches(type, data, path)
    missing = type.from(data).to_h.filter_map { |name, field| name if field.nil? } - type.optional_members
    missing.map { "#{path} lacks #{it}" } + unknown_keys(type, data, path)
  end

  def typed_resources(appliance)
    types = { 'Ident' => Miele::Sdk::Schema::DeviceIdentification, 'State' => Miele::Sdk::Schema::DeviceState,
              'SuperVision' => Miele::Sdk::Schema::SuperVision }
    found = types.filter_map do |resource, type|
      [type, appliance.get("/Devices/#{appliance.fab}/#{resource}"), "#{appliance.host} #{resource}"]
    rescue Miele::Sdk::NotFoundError
      raise unless resource == 'SuperVision'

      nil # a hob serves no SuperVision
    end
    found << [Miele::Sdk::Schema::ModuleUpdateInfo, appliance.get('/Update/'), "#{appliance.host} /Update/"]
  end

  it 'reads each typed resource with the fields the app requires and no key its class lacks' do
    found = appliances.flat_map { typed_resources(it) }.flat_map { |type, data, path| mismatches(type, data, path) }
    expect(found).to be_empty
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
