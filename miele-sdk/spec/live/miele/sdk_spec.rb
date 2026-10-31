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
      raise "live specs are read-only: #{verb.upcase} refused" unless verb == :get || dop1_read?(rest.first, options)

      original.call(host, verb, *rest, **options)
    end
    allow(Miele::Sdk::Cloud::Http).to receive(:request).and_wrap_original do |original, verb, url, **options|
      account = verb == :post && url.match?(%r{/(V3/Login|V2/AppTokenRefresh)\b|/token\z})
      raise "live specs are read-only: #{verb.upcase} refused" unless verb == :get || account

      original.call(verb, url, **options)
    end
  end

  def dop1_read?(path, options)
    path.to_s.end_with?('/DOP/') && JSON.parse(options[:body].to_s)['Request'].to_s[4, 2] == Miele::Sdk::Dop1::READ
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

  it "reads the hood and hob ExtendedState as the app's Dop1 objects, nil when they serve none" do
    states = appliances.select { %i[hood hob_highlight hob_induction hob_gas].include?(it.device_type) }.map(&:state)
    skip 'no hood or hob among MIELE_HOSTS' if states.empty?
    decoded = states.map { [it.raw['ExtendedState'].to_s.empty?, it.extended_state] }
    expect(decoded).to all(satisfy { |empty, value| empty ? value.nil? : value.is_a?(Data) })
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

  it 'reads the hood as the app does once it serves ExtendedState' do
    hood = appliances.find { it.is_a?(Miele::Sdk::Hood) } or skip 'no hood among MIELE_HOSTS'
    pending 'switch the hood on to read it' if hood.state.raw['ExtendedState'].to_s.empty?
    expect([hood.fan_level, hood.run_on, hood.lights, hood.grease_filter, hood.charcoal_filter]).to all(be)
  end

  it 'reads the hob as the app does once it serves ExtendedState' do
    hob = appliances.find { it.is_a?(Miele::Sdk::Hob) } or skip 'no hob among MIELE_HOSTS'
    pending 'switch the hob on to read it' if hob.state.raw['ExtendedState'].to_s.empty?
    expect(hob.zones).to all(be_a(Miele::Sdk::Hob::Zone)).and(be_any)
  end

  it 'gets a NotFoundError for a dop2 leaf from appliances that serve no DOP2', :aggregate_failures do
    appliances.reject { it.get("/Devices/#{it.fab}/").key?('DOP2') }.each do |appliance|
      expect { appliance.dop2(2, 1586) }.to raise_error(Miele::Sdk::NotFoundError)
    end
  end

  it 'cannot write' do
    expect { appliances.first.wake }.to raise_error(RuntimeError, /read-only: PUT refused/)
  end

  context 'with the Miele account' do
    let(:cloud) { described_class.cloud }
    let(:ovens) { [12, 13, 15, 31, 39, 45] }

    before do
      skip 'set MIELE_COUNTRY' unless ENV.key?('MIELE_COUNTRY')
      described_class.configure do |config|
        config.country = ENV.fetch('MIELE_COUNTRY')
        config.email = ENV.fetch('MIELE_EMAIL', nil)
        config.password = ENV.fetch('MIELE_PASSWORD', nil)
        config.token_file = ENV.fetch('MIELE_TOKEN_FILE', nil)
        config.ciam_client_id = ENV.fetch('MIELE_CIAM_CLIENT_ID', nil)
      end
      cloud or skip 'set MIELE_EMAIL or MIELE_TOKEN_FILE'
      cloud.session.authorization
    rescue Miele::Sdk::ConfigurationError => e
      skip e.message
    end

    it 'logs in and lists the account appliances' do
      expect(described_class.appliances)
        .to all(have_attributes(fab: match(/\A\d+\z/), host: match(/\.local\.?\z/))).and(be_any)
    end

    it 'reads each appliance state through the cloud' do
      states = cloud.devices.map { JSON.parse(cloud.request(:get, "/Devices/#{it.fab}/State").body) }
      expect(states).to all(include('Status'))
    end

    it 'reads the oven DeviceContext 1/1585 through the cloud' do
      oven = cloud.devices.find { ovens.include?(it.ident&.fetch('DeviceType', nil)) } or skip 'no oven in this account'
      leaf = Miele::Sdk::Dop2.decode(cloud.request(:get, "/Devices/#{oven.fab}/DOP2/1/1585").body)
      expect([leaf.unit, leaf.attribute]).to eq([1, 1585])
    end

    it 'reads the oven DeviceContext as a typed value, through the cloud' do
      oven = appliances.find { it.device_type.start_with?('oven') } or skip 'no oven among MIELE_HOSTS'
      expect(oven.object(Miele::Sdk::Objects::Oven::GlobalDeviceContext))
        .to be_a(Miele::Sdk::Objects::Oven::GlobalDeviceContext)
    end

    it 'gives the oven its family class and reads it as the app does', :aggregate_failures do
      oven = described_class.appliances.find { it.is_a?(Miele::Sdk::Oven) } or skip 'no oven in this account'
      objects = Miele::Sdk::Objects::Oven
      expect([oven.context, oven.program_context, oven.notifications])
        .to match([an_instance_of(objects::GlobalDeviceContext), an_instance_of(objects::GlobalPsContext),
                   an_instance_of(objects::GlobalNtfctnShow)])
      expect(oven.target_temperature).to be_nil.or(be_a(Float))
    end

    it "reads the hood's ColorFlow and Con@ctivity Plus, nil where it has none" do
      hood = appliances.find { it.is_a?(Miele::Sdk::Hood) } or skip 'no hood among MIELE_HOSTS'
      expect([hood.color_flow, hood.connectivity_plus]).to all(be_nil.or(be_a(Data)))
    end

    it 'reads the household key from the cloud and signs locally with it', :aggregate_failures do
      expect(cloud.group == [ENV.fetch('MIELE_GROUP_ID'), ENV.fetch('MIELE_GROUP_KEY')]).to be(true)
      described_class.configure do |config|
        config.group_id = nil
        config.group_key = nil
      end
      expect(appliances.map(&:device_type)).not_to include(:unknown)
    end
  end
end
