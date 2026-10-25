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

  it 'gives every registered type an entry method and its RBS signature', :aggregate_failures do
    described_class::REGISTRY.each_key do |type|
      name = type.split('_').map(&:capitalize).join
      expect(Hue::Sdk).to respond_to(name)
      expect(signatures).to have_key(name.to_sym)
    end
  end
end
