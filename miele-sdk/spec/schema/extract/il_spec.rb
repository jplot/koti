# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../schema/extract/il'

RSpec.describe Schema::Extract::Il do
  subject(:classes) { described_class.read([path]) }

  let(:path) { File.join(Dir.mktmpdir, 'Miele.Rest.il') }
  let(:json) { '    .custom instance void [Newtonsoft.Json]Newtonsoft.Json' }
  let(:nullable) { '.custom instance void [System.Runtime]System.Runtime.CompilerServices.Nullable' }

  before do
    File.write(path, <<~IL)
      .class public auto ansi sealed Miele.Rest.DeviceStateStatus
             extends [System.Runtime]System.Enum
      {
      } // end of class Miele.Rest.DeviceStateStatus

      .class public auto ansi sealed beforefieldinit Miele.Rest.DeviceIdentificationDto
             extends [System.Runtime]System.Object
      {
        #{nullable}ContextAttribute::.ctor(uint8) = ( 01 00 02 00 00 )
        .property instance [System.Runtime]System.Nullable`1<int32>
                DeviceType()
        {
      #{json}.JsonPropertyAttribute::.ctor(string) = ( 01 00 0A 44 65 76 69 63 65 54 79 70 65 00 00 )    // ...DeviceType..
        } // end of property DeviceIdentificationDto::DeviceType
        .property instance class Miele.Rest.DeviceIdentificationLabelDto
                DeviceIdentificationLabel()
        {
      #{json}.JsonPropertyAttribute::.ctor(string) = ( 01 00 10 44 65 76 69 63 65 49 64 65 6E 74 4C 61   // ...DeviceIdentLa
                                                                                                        62 65 6C 00 00 )                                  // bel..
        } // end of property DeviceIdentificationDto::DeviceIdentificationLabel
        .property instance class Miele.Rest.DeviceStateStatus Status()
        {
        } // end of property DeviceIdentificationDto::Status
        .property instance int32 Count()
        {
        } // end of property DeviceIdentificationDto::Count
        .property instance class Miele.Rest.PeerDto[] Peers()
        {
          #{nullable}Attribute::.ctor(uint8[]) = ( 01 00 02 00 00 00 01 02 00 00 )
        } // end of property DeviceIdentificationDto::Peers
        .property instance string Name()
        {
          .custom instance void [System.Text.Json]System.Text.Json.Serialization.JsonPropertyNameAttribute::.ctor(string) = ( 01 00 04 6E 61 6D 65 00 00 )
        } // end of property DeviceIdentificationDto::Name
        .property instance string Secret()
        {
      #{json}.JsonIgnoreAttribute::.ctor() = ( 01 00 00 00 )
        } // end of property DeviceIdentificationDto::Secret
        .property instance class [System.Runtime]System.Type EqualityContract()
        {
        } // end of property DeviceIdentificationDto::EqualityContract
        .property instance string Item(int32)
        {
        } // end of property DeviceIdentificationDto::Item
      } // end of class Miele.Rest.DeviceIdentificationDto

      .class public auto ansi sealed beforefieldinit Miele.Dtos.SuperVisionDto
      {
        #{nullable}ContextAttribute::.ctor(uint8) = ( 01 00 01 00 00 )
        .method public hidebysig instance bool Equals(class Miele.Dtos.SuperVisionDto other) cil managed
        {
          #{nullable}ContextAttribute::.ctor(uint8) = ( 01 00 02 00 00 )
        } // end of method SuperVisionDto::Equals
        .property instance bool Enabled()
        {
        } // end of property SuperVisionDto::Enabled
        .property instance [System.Runtime]System.Nullable`1<bool> Signal()
        {
        } // end of property SuperVisionDto::Signal
        .property instance string Note()
        {
          #{nullable}Attribute::.ctor(uint8) = ( 01 00 02 00 00 )
        } // end of property SuperVisionDto::Note
        .property instance string Resource()
        {
      #{json}.JsonPropertyAttribute::.ctor() = ( 01 00 02 00 54 08 05 4F 72 64 65 72 01 00 00 00   // ....T..Order....
                                                                                                54 0E 0C 50 72 6F 70 65 72 74 79 4E 61 6D 65 04   // T..PropertyName.
                                                                                                50 61 74 68 )                                     // Path
        } // end of property SuperVisionDto::Resource
        .property instance string Bare()
        {
      #{json}.JsonPropertyAttribute::.ctor() = ( 01 00 00 00 )
        } // end of property SuperVisionDto::Bare
        .property instance [System.Runtime]System.Collections.Generic.IDictionary`2<string,object>
                Entries()
        {
      #{json}.JsonExtensionDataAttribute::.ctor() = ( 01 00 00 00 )
        } // end of property SuperVisionDto::Entries
      } // end of class Miele.Dtos.SuperVisionDto

      .class public auto ansi beforefieldinit Miele.Recipes.ResponseDto`1<class TModel>
             extends [System.Runtime]System.Object
      {
        .property instance !TModel Data()
        {
        } // end of property ResponseDto`1::Data
      } // end of class Miele.Recipes.ResponseDto`1
    IL
  end

  after { FileUtils.remove_entry(File.dirname(path)) }

  def nullability(name) = classes.fetch(name).fetch('fields').transform_values { it['nullable'] }

  it 'names each field by its JsonProperty or JsonPropertyName, else its property, leaving out the others' do
    expect(classes.transform_values { it['fields'].keys }).to eq(
      'Miele.Rest.DeviceStateStatus' => [], 'Miele.Recipes.ResponseDto`1' => %w[Data],
      'Miele.Rest.DeviceIdentificationDto' => %w[DeviceType DeviceIdentLabel Status Count Peers name],
      'Miele.Dtos.SuperVisionDto' => %w[Enabled Signal Note Path Bare]
    )
  end

  it 'reads a Nullable, a value type, then a reference by its own flag or its class context', :aggregate_failures do
    expect(nullability('Miele.Rest.DeviceIdentificationDto')).to eq(
      'DeviceType' => true, 'DeviceIdentLabel' => true, 'Status' => false, 'Count' => false, 'Peers' => false,
      'name' => true
    )
    expect(nullability('Miele.Dtos.SuperVisionDto'))
      .to eq('Enabled' => false, 'Signal' => true, 'Note' => true, 'Path' => false, 'Bare' => false)
  end

  it 'keeps the CLR type of each field' do
    expect(classes.dig('Miele.Rest.DeviceIdentificationDto', 'fields', 'Status', 'type'))
      .to eq('class Miele.Rest.DeviceStateStatus')
  end

  it 'tells which class gathers the keys it does not declare' do
    expect(classes.transform_values { it['extension'] }.select { |_, gathers| gathers }.keys)
      .to eq(['Miele.Dtos.SuperVisionDto'])
  end
end
