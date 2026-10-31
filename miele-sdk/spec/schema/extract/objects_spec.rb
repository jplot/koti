# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../schema/extract/objects/extract'

RSpec.describe Schema::Extract::Objects do
  let(:il) { Dir[File.join(__dir__, '../../fixtures/il/*.il')] }
  let(:classes) { il.flat_map { Schema::Extract::Objects::IlModel.parse(it) } }
  let(:layouts) { Schema::Extract::Objects::Layouts.new(classes) }
  let(:table) do
    File.join(Dir.mktmpdir, 'addresses.tsv').tap do |path|
      File.write(path, "# family\tname\tunit\tattribute\tidx1\tidx2\n" \
                       "oven\tGLOBAL_PS_Select\t2\t1577\t0\t0\t# PsSelectMessage\n")
    end
  end

  def oven(name) = "Miele.Modules.Oven.ApplianceCommunication.Protocols.DOP2.#{name}"

  def field(klass, name) = layouts.dop2.fetch(oven(klass))['fields'].find { it['name'] == name }

  it 'reads a DOP2 class with its fields and wire types' do
    expect(field('GLOBAL_PS_SelectionParaCA', 'Temperature'))
      .to eq('index' => 6, 'name' => 'Temperature', 'kind' => 'scalar', 'wire' => 5, 'type' => nil)
  end

  it 'reads an enum field without a wire width' do
    expect(field('GLOBAL_PS_Select', 'SelectionType'))
      .to include('index' => 3, 'kind' => 'enum', 'wire' => nil, 'type' => oven('Enums/GLOBAL_EnumSelectionType'))
  end

  it 'keeps two getters on one index' do
    fields = layouts.dop2.fetch(oven('GLOBAL_PS_AttributesCCA'))['fields'].select { it['index'] == 5 }
    expect(fields.map { it['name'] }).to contain_exactly('TotalRemainingTime', 'Level')
  end

  it 'reads a Dop1 object with its id, endianness and sections', :aggregate_failures do
    name = 'Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung'
    object = layouts.dop1.fetch(name)
    expect(object).to include('id' => '8E01', 'endian' => 'msb')
    expect(object['sections']).to contain_exactly(include('offset' => 0, 'length' => 4))
    expect(layouts.dop1.fetch(object['sections'].first['type'])['fields'])
      .to include(include('name' => 'Luefterstufe', 'kind' => 'u8', 'offset' => 2, 'size' => 1))
  end

  it 'drops the quotes ikdasm puts around a name outside ASCII', :aggregate_failures do
    enum = 'Miele.Modules.Hobs.ApplianceCommunication.ApplianceData.Dop1.Enums/BestätigungNotwendigEnum'
    expect(layouts.enums).to include(enum)
    expect(layouts.dop1.fetch('Kochstelle_1')['fields']).to include(include('type' => enum))
    expect(layouts.dop1.fetch('Info_Kochstelle_Kochstelle_1')['fields'])
      .to include(include('name' => 'Topfgroeße_erkannt_Variokochzone_1', 'kind' => 'bits'))
  end

  it 'gives a Dop1 object the parts of the object it extends' do
    hood = 'Miele.Modules.Hoods.ApplianceCommunication.ApplianceData'
    expect(layouts.dop1.fetch("#{hood}.ExtendedDopDeviceState")).to include(
      'id' => '1000', 'endian' => 'msb',
      'sections' => [include('type' => "#{hood}.DeviceState/Struktur_VersionSection", 'offset' => 0, 'length' => 1)]
    )
  end

  it 'writes the pieces a write section sends, the bit field it holds included' do
    name = 'Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData.DW.DOP.' \
           'SmartControl_GSD_Programmwahl_Setzen/SettingsWriteSection'
    expect(layouts.dop1.fetch(name)['write_bytes']).to eq([[0, 1], [1, 1], [2, 2]])
  end

  it 'takes the byte order of a write section the app builds alone' do
    name = 'Miele.Modules.Hoods.ApplianceCommunication.ApplianceData.ServiceDataExt_Lueftersteuerung/' \
           'ServiceDataExt_LueftersteuerungWriteSection'
    expect(layouts.dop1.fetch(name)['endian']).to eq('msb')
  end

  it 'finds an address from each call-site idiom' do
    found = Schema::Extract::Objects::Addresses.new(classes, layouts.dop2).find
    expect(found.transform_keys { it.split('.').last }).to include(
      'GLOBAL_OP_ProgramInfoCA' => [[2, 213, 0, 1]], 'GLOBAL_PS_Context' => [[2, 1574]],
      'GLOBAL_SF_Value' => [[2, 105, 12_037, 1]]
    )
  end

  it 'takes the addresses of the table and counts its classes as used', :aggregate_failures do
    data, = described_class.extract(il, table)
    select = data['dop2'].find { it['family'] == 'oven' && it['name'] == 'GLOBAL_PS_Select' }
    expect(select['addresses']).to eq([[2, 1577, 0, 0]])
    expect(data['dop2'].map { it['name'] }).to include('GLOBAL_PS_SelectionParaCA')
    expect(data['enums'].map { it['name'] }).to include('GLOBAL_EnumSelectionType')
  end

  it 'names the class of a Dop1 section as it names the class itself' do
    data, = described_class.extract(il, table)
    object = data['dop1'].find { it['family'] == 'hood' && it['name'] == 'ServiceDataExt_Lueftersteuerung' }
    expect(object['sections'].map { it['type'] })
      .to eq(['ServiceDataExt_Lueftersteuerung/ServiceDataExt_LueftersteuerungSection'])
  end

  it 'reports a call-site address the table lacks' do
    _, disagreements = described_class.extract(il, table)
    expect(disagreements)
      .to include(a_string_starting_with('oven GLOBAL_OP_ProgramInfoCA: the call sites give [[2, 213, 0, 1]]'))
  end

  it 'takes an index the table computes as covering any value at the call sites' do
    path = File.join(Dir.mktmpdir, 'addresses.tsv')
    File.write(path, "laundry\tGLOBAL_SF_Value\t2\t105\t-\t1\n")
    _, disagreements = described_class.extract(il, path)
    expect(disagreements).not_to include(a_string_starting_with('laundry GLOBAL_SF_Value'))
  end

  describe 'the extracted file' do
    let(:data) do
      JSON.parse(Zlib.gunzip(File.binread(File.join(__dir__, '../../../lib/miele/sdk/objects/objects.json.gz'))))
    end

    it 'counts the expected classes' do
      expect(data.transform_values(&:size)).to eq('dop2' => 402, 'dop1' => 468, 'enums' => 336)
    end

    it 'has an address for every class the app reads or writes' do
      held = data['dop2'].flat_map do |klass|
        klass['fields'].filter_map { [klass['family'], it['type']] if it['kind'].start_with?('struct') }
      end
      read = data['dop2'].reject { held.include?([it['family'], it['name']]) }
      expect(read.select { it['addresses'].empty? }.map { it['name'] }).to be_empty
    end
  end
end
