# frozen_string_literal: true

RSpec.describe Hue::Sdk, :live do
  before do
    missing = %w[HUE_HOST HUE_BRIDGE_ID HUE_APPLICATION_KEY].reject { ENV.key?(it) }
    skip "set #{missing.join(', ')}" unless missing.empty?
    described_class.configure do |config|
      config.host = ENV.fetch('HUE_HOST')
      config.bridge_id = ENV.fetch('HUE_BRIDGE_ID')
      config.application_key = ENV.fetch('HUE_APPLICATION_KEY')
    end
    allow(Hue::Sdk::Connection).to receive(:request).and_wrap_original do |original, verb, *arguments, **options|
      raise "live specs are read-only: #{verb.upcase} refused" unless verb == :get

      original.call(verb, *arguments, **options)
    end
  end

  it 'discovers the configured bridge' do
    expect(described_class.discover.map(&:bridge_id)).to include(ENV.fetch('HUE_BRIDGE_ID').upcase)
  end

  it 'lists lights', :aggregate_failures do
    lights = described_class.Light.list
    expect(lights).not_to be_empty
    expect(lights).to all(be_a(Hue::Sdk::Models::Light::Instance))
  end

  def missing(value, path)
    value.class.members.flat_map do |name|
      field = value.public_send(name)
      next(value.class.optional_members.include?(name) ? [] : ["#{path}.#{name}"]) if field.nil?

      Array(field).grep(Hue::Sdk::Schema::Value).flat_map { missing(it, "#{path}.#{name}") }
    end
  end

  it 'reads every resource as a typed value holding its required fields' do
    values = Hue::Sdk::Client.get('/resource').filter_map do |data|
      Hue::Sdk::Models::REGISTRY[data['type']]&.then { it::Instance.new(data['id'], data:).attributes }
    end
    expect(values.flat_map { missing(it, it.class.name) }).to be_empty
  end

  it 'registers every resource type the firmware supports' do
    supported = described_class.Clip.list.first['resources'] - %w[private_group private_scene]
    expect(supported - Hue::Sdk::Models::REGISTRY.keys).to be_empty
  end

  it 'holds the event stream open' do
    listener = Thread.new { Hue::Sdk::Events::Stream.new(sleeper: ->(_) { raise 'the stream broke' }).each { nil } }
    expect(listener.join(3)).to be_nil
  ensure
    listener&.kill
  end

  it 'cannot write' do
    light = described_class.Light.list.first
    expect { light.update(on: light['on']) }.to raise_error(RuntimeError, /read-only: PUT refused/)
  end
end
