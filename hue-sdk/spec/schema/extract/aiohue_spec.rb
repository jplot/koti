# frozen_string_literal: true

require_relative '../../../schema/extract/aiohue'

RSpec.describe Schema::Extract::Aiohue do
  subject(:aiohue) { described_class.read(directory) }

  let(:directory) { Dir.mktmpdir }

  before do
    File.write(File.join(directory, 'light.py'), <<~PYTHON)
      from dataclasses import dataclass
      from enum import Enum


      class LightMode(Enum):
          NORMAL = "normal"
          STREAMING = "streaming"


      @dataclass
      class Resource:
          id: str
          type: ResourceTypes = ResourceTypes.UNKNOWN


      @dataclass
      class Light(Resource):
          mode: LightMode
          type: ResourceTypes = ResourceTypes.LIGHT


      @dataclass
      class LightPut:
          mode: LightMode | None = None


      @dataclass
      class NewLightPost:
          type: ResourceTypes = ResourceTypes.LIGHT
    PYTHON
  end

  after { FileUtils.remove_entry(directory) }

  it 'reads a dataclass with the fields it inherits' do
    expect(aiohue.fields('Light').map { it.values_at('name', 'type', 'default') })
      .to eq([%w[id str] + [nil], %w[mode LightMode] + [nil], %w[type ResourceTypes ResourceTypes.LIGHT]])
  end

  it 'reads the values of an enum' do
    expect(aiohue.values('LightMode')).to eq(%w[normal streaming])
  end

  it 'finds the class of a resource type by the type it defaults to' do
    expect(%w[added update add].map { aiohue.class_for('light', it) }).to eq(%w[Light LightPut NewLightPost])
  end

  it 'requires a response field without default that cannot be None' do
    expect(%w[mode type].map { described_class.required?(aiohue.field('Light', it)) }).to eq([true, false])
  end

  it 'raises when the directory holds no aiohue model' do
    expect { described_class.read(File.join(directory, 'aiohue')) }.to raise_error(ArgumentError, /no aiohue class/)
  end
end
