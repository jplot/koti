# frozen_string_literal: true

require_relative '../../../schema/extract/responses'

RSpec.describe Schema::Extract::Responses do
  subject(:responses) { described_class.new(Schema::Extract::Snapshot.new(directory, ->(address, _) { code.fetch(address) })) }

  let(:directory) do
    blutter_output(
      'asm/bridge_control/src/raml_code.added.dart' => <<~DART,
        class LightAdded extends ResourceAdded {
          factory _ LightAdded.fromJson(/* No info */) {
            // ** addr: 0x300, size: 0x40
          }
        }
        class DimmingAdded extends Object {
          factory _ DimmingAdded.fromJson(/* No info */) {
            // ** addr: 0x500, size: 0x10
          }
        }
      DART
      'asm/bridge_control/src/raml_code.update.dart' => "class LightUpdate extends ResourceUpdate {\n}\n",
      'asm/bridge_control/src/raml_code.add.dart' => '',
      'pp.txt' => <<~POOL
        [pp+0x10] String: "on"
        [pp+0x18] Type: bool
        [pp+0x1020] String: "dimming"
        [pp+0x28] String: "ids"
        [pp+0x30] TypeArguments: <String>
        [pp+0x38] String: "mode"
        [pp+0x40] String: "brightness"
        [pp+0x48] Type: double
      POOL
    )
  end
  let(:code) do
    { 0x300 => ["ldr\tx2, [x27, #0x10]", "blr\tx30", "ldr\tx1, [x27, #0x18]", "ldr\tx1, [x27, #0x48]",
                "add\tx2, x27, #0x1, lsl #12", "ldr\tx2, [x2, #0x20]", "blr\tx30", "bl\t0x500",
                "ldr\tx2, [x27, #0x28]", "blr\tx30", "ldr\tx3, [x27, #0x30]",
                "ldr\tx2, [x27, #0x38]", "bl\t0x900", "bl\t0x300"],
      0x500 => ["ldr\tx2, [x27, #0x40]", "blr\tx30", "ldr\tx1, [x27, #0x48]"] }
  end

  after { FileUtils.remove_entry(directory) }

  it 'reads the key each fromJson decodes, with the first type, class or list item loaded for it' do
    expect(responses.read['added']).to eq(
      'LightAdded' => { 'on' => { 'type' => 'bool' }, 'dimming' => { 'class' => 'DimmingAdded' },
                        'ids' => { 'items' => 'String' }, 'mode' => {} },
      'DimmingAdded' => { 'brightness' => { 'type' => 'double' } }
    )
  end

  it 'lists the classes of every kind, without fields when blutter lists no fromJson' do
    expect(responses.read.slice('update', 'add')).to eq('update' => { 'LightUpdate' => nil }, 'add' => {})
  end
end
