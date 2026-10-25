# frozen_string_literal: true

require 'rbs'

RSpec.describe Hue::Sdk::Models do
  let(:signatures) do
    loader = RBS::EnvironmentLoader.new
    loader.add(path: Pathname('sig'))
    %w[singleton net-http openssl socket json resolv].each { |library| loader.add(library:) }
    env = RBS::Environment.from_loader(loader).resolve_type_names
    RBS::DefinitionBuilder.new(env:).build_singleton(RBS::TypeName.parse('::Hue::Sdk')).methods
  end

  # The `clip` resource of a Bridge Pro on swversion 2071524040 lists these types, plus
  # private_group and private_scene, which answer 404 to application keys.
  let(:firmware_types) do
    %w[behavior_instance behavior_script behavior_script_formula bell_button bridge bridge_home button
       camera_motion clip contact convenience_area_motion device device_power device_software_update
       entertainment entertainment_configuration geofence_client geolocation grouped_light
       grouped_light_level grouped_motion light light_level matter matter_fabric motion
       motion_area_candidate motion_area_configuration power_output_configuration relative_rotary room
       scene security_area_motion service_group smart_scene speaker switch_input_configuration tamper
       temperature zgp_connectivity zigbee_connectivity zigbee_device_discovery zone]
  end

  let(:app_operations) do
    {
      'behavior_instance' => %i[create update delete], 'behavior_script_formula' => %i[create delete],
      'clip' => [], 'entertainment_configuration' => %i[create update delete],
      'matter_fabric' => %i[update delete], 'motion_area_configuration' => %i[create update delete],
      'power_output_configuration' => %i[update], 'service_group' => %i[create update delete]
    }
  end

  it 'gives every registered type an entry method and its RBS signature', :aggregate_failures do
    described_class::REGISTRY.each_key do |type|
      name = type.split('_').map(&:capitalize).join
      expect(Hue::Sdk).to respond_to(name)
      expect(signatures).to have_key(name.to_sym)
    end
  end

  it 'registers every resource type the Bridge Pro firmware advertises' do
    expect(firmware_types - described_class::REGISTRY.keys).to be_empty
  end

  it 'allows the operations confirmed for these types', :aggregate_failures do
    app_operations.each do |type, operations|
      collection = Hue::Sdk.resource(type)
      resource = Hue::Sdk.resource(type, 'id')
      granted = { create: collection, update: resource, delete: resource }.select { |name, on| on.respond_to?(name) }
      expect(granted.keys).to eq(operations), type
    end
  end
end
