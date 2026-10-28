# frozen_string_literal: true

require_relative '../../../schema/extract/snapshot'

RSpec.describe Schema::Extract::Snapshot do
  subject(:snapshot) { described_class.new(directory, ->(address, size) { [[address, size]] }) }

  let(:directory) do
    blutter_output('asm/bridge_control/src/raml_code.added.dart' => <<~DART, 'pp.txt' => <<~POOL)
      class LightAdded extends ResourceAdded {

        Map<String, Object?> toJson(LightAdded) {
          // ** addr: 0x100, size: 0x48
        }
        Map<String, Object?> toJson(LightAdded) {
          // ** addr: 0x200, size: 0xa0
        }
        factory _ LightAdded.fromJson(/* No info */) {
          // ** addr: 0x300, size: 0x170
        }
      }
    DART
      pool heap offset: 0x3400080
      [pp+0x10] String: "on"
      [pp+0x18] Type: LightAdded
    POOL
  end

  after { FileUtils.remove_entry(directory) }

  it 'names the function holding an address, or ending right before it' do
    expect([0x300, 0x46c, 0x470, 0x474, 0xff].map { snapshot.owner(it) })
      .to eq([*Array.new(3, 'LightAdded.LightAdded.fromJson'), nil, nil])
  end

  it 'finds the largest of the functions sharing a name' do
    expect(snapshot.function('LightAdded.toJson')).to eq([0x200, 0xa0])
  end

  it 'reads the objects and strings of the object pool', :aggregate_failures do
    expect(snapshot.object(0x18)).to eq('Type: LightAdded')
    expect([snapshot.string(0x10), snapshot.string(0x18)]).to eq(['on', nil])
  end

  it 'disassembles through the disassembler it was given' do
    expect(snapshot.instructions(0x300, 0x10)).to eq([[0x300, 0x10]])
  end

  it 'locates the listing of a Dart library' do
    expect(File.read(snapshot.source('bridge_control/src/raml_code.added.dart'))).to start_with('class LightAdded')
  end
end
