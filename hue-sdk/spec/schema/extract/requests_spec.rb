# frozen_string_literal: true

require_relative '../../../schema/extract/requests'

RSpec.describe Schema::Extract::Requests do
  subject(:requests) do
    described_class.new(Schema::Extract::Snapshot.new(directory, ->(address, _) { code.fetch(address) }), responses)
  end

  let(:directory) do
    blutter_output(
      'asm/bridge_control/src/raml_code.update.dart' => <<~DART,
        class LightUpdate extends ResourceUpdate {

          OnFeatureUpdate field_c;

          Map<String, Object?> toJson(LightUpdate) {
            // ** addr: 0x600, size: 0x48
          }
        }
        class OnFeatureUpdate extends Object {

          Map<String, Object?> toJson(OnFeatureUpdate) {
            // ** addr: 0x800, size: 0x60
          }
        }
      DART
      'asm/bridge_control/src/raml_code.add.dart' => <<~DART,
        class SceneMappingAdd extends Object {

          Map<String, Object?> toJson(SceneMappingAdd) {
            // ** addr: 0xa00, size: 0x60
          }
        }
      DART
      'pp.txt' => <<~POOL
        [pp+0x10] String: "on"
        [pp+0x40] String: "brightness"
        [pp+0x50] String: "type"
        [pp+0x58] String: "duration"
        [pp+0x1060] String: "on"
        [pp+0x1068] String: "version"
        [pp+0x1070] String: "algorithm"
        [pp+0x2008] String: "spatial"
        [pp+0x78] String: "second"
        [pp+0x80] String: "minute"
      POOL
    )
  end
  let(:responses) do
    { 'update' => { 'LightUpdate' => { 'on' => { 'class' => 'OnFeatureUpdate' } }, 'OnFeatureUpdate' => nil },
      'add' => { 'SceneMappingAdd' => nil } }
  end
  let(:code) do
    { 0x600 => %W[bl\t0x650 ret], 0x650 => %W[bl\t0x700 ret],
      0x700 => [*Array.new(8, "mov\tx29, x15"), "ldur\tw3, [x4, #0xb]", "cmp\tw3, w22",
                "ldr\tx2, [x27, #0x10]", "blr\tx30", "ldur\td0, [x4, #0x13]", "ldur\tx7, [x4, #0x20]",
                "ldr\tx2, [x27, #0x40]", "bl\t0x900", "ldr\tx16, [x27, #0x50]", "ldur\tw5, [x4, #0x7]",
                "ldur\tx6, [x4, #0x1b]", "ldr\tx2, [x27, #0x58]", "blr\tx30", 'ret'],
      0x800 => ["ldur\tw3, [x1, #0x7]", "cmp\tw9, w22", "add\tx2, x27, #0x1, lsl #12", "ldr\tx2, [x2, #0x60]",
                "blr\tx30", "add\tx16, x27, #0x1, lsl #12", "ldr\tx16, [x16, #0x68]", "ldur\tw5, [x1, #0xf]"],
      0xa00 => ["ldur\tx6, [x1, #0xf]", "ldr\tx2, [x27, #0x80]", "blr\tx30",
                "add\tx2, x27, #0x1, lsl #12", "ldr\tx2, [x2, #0x70]", "add\tx3, x27, #0x2, lsl #12",
                "ldr\tx3, [x3, #0x8]", "blr\tx30", "ldr\tx2, [x27, #0x78]", "mov\tx3, #0x0", "blr\tx30"] }
  end

  after { FileUtils.remove_entry(directory) }

  it 'reads the keys a toJson writes, through two tear-offs, and which it writes without a null check' do
    expect(requests.read.dig('update', 'LightUpdate', 'written')).to eq(
      'on' => { 'offset' => 0xc, 'kind' => 'pointer', 'required' => false },
      'brightness' => { 'offset' => 0x14, 'kind' => 'double', 'required' => true },
      'type' => { 'offset' => 0x8, 'kind' => 'pointer', 'required' => true },
      'duration' => { 'offset' => 0x1c, 'kind' => 'int', 'required' => true }
    )
  end

  it 'leaves a field required when the null check tests another register, and reads a paged map key' do
    expect(requests.read.dig('update', 'OnFeatureUpdate', 'written'))
      .to eq('on' => { 'offset' => 0x8, 'kind' => 'pointer', 'required' => true },
             'version' => { 'offset' => 0x10, 'kind' => 'pointer', 'required' => true })
  end

  it 'writes a key whose value is a constant string or integer, not the field written before it' do
    expect(requests.read.dig('add', 'SceneMappingAdd', 'written'))
      .to eq('minute' => { 'offset' => 0x10, 'kind' => 'int', 'required' => true },
             'algorithm' => { 'kind' => 'string', 'required' => true },
             'second' => { 'kind' => 'int', 'required' => true })
  end

  it 'keeps what fromJson decodes and the fields blutter types, by offset' do
    expect(requests.read.dig('update', 'LightUpdate').slice('decoded', 'declared'))
      .to eq('decoded' => { 'on' => { 'class' => 'OnFeatureUpdate' } }, 'declared' => { 0xc => 'OnFeatureUpdate' })
  end
end
