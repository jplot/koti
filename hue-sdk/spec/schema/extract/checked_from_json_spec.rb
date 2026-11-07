# frozen_string_literal: true

require_relative '../../../schema/extract/secure'

RSpec.describe Schema::Extract::CheckedFromJson do
  subject(:classes) { Schema::Extract::SecureClasses.new(snapshot, taken: []).read(roots) }

  let(:roots) { %w[CameraMetadataResponse CameraServiceResponse] }
  let(:snapshot) { Schema::Extract::Snapshot.new(directory, ->(address, _) { code.fetch(address) }) }
  let(:directory) do
    blutter_output('asm/security/src/camera_settings/api/http/response/camera.dart' => <<~DART, 'pp.txt' => <<~POOL)
      class :: {
        static _ _$CameraMetadataResponseFromJson(/* No info */) {
          // ** addr: 0x1000, size: 0x40
        }
        static _ _$CameraServiceResponseFromJson(/* No info */) {
          // ** addr: 0x2000, size: 0x40
        }
        static _ _$CameraCameraServiceResponseFromJson(/* No info */) {
          // ** addr: 0x3000, size: 0x40
        }
        static Y0 $checkedCreate<Y0>(/* No info */) {
          // ** addr: 0x9000, size: 0x40
        }
      }
    DART
      [pp+0x10] AnonymousClosure: static (0x1100), in [package:security/src/camera.dart] ::_$CameraMetadataResponseFromJson (0x1000)
      [pp+0x18] AnonymousClosure: static (0x1200), in [package:security/src/camera.dart] ::_$CameraMetadataResponseFromJson (0x1000)
      [pp+0x20] AnonymousClosure: static (0x1300), in [package:security/src/camera.dart] ::_$CameraMetadataResponseFromJson (0x1000)
      [pp+0x28] TypeArguments: <String>
      [pp+0x30] String: "name"
      [pp+0x38] String: "archetype"
      [pp+0x40] Type: String
      [pp+0x48] Type: String?
      [pp+0x50] AnonymousClosure: static (0x2100), in [package:security/src/camera.dart] ::_$CameraServiceResponseFromJson (0x2000)
      [pp+0x58] AnonymousClosure: static (0x2200), in [package:security/src/camera.dart] ::_$CameraServiceResponseFromJson (0x2000)
      [pp+0x60] TypeArguments: <Map<String, CameraCameraServiceResponse>?>
      [pp+0x68] String: "camera"
      [pp+0x70] Type: Map<String, dynamic>?
      [pp+0x78] String: "enabled"
      [pp+0x80] Type: bool?
      [pp+0x1010] TypeArguments: <String>
    POOL
  end
  let(:code) do
    { 0x1000 => ["add\tx1, x27, #0x0, lsl #12", "ldr\tx1, [x1, #0x10]", "bl\t0x9000", 'ret'],
      0x1100 => ["ldr\tx1, [x27, #0x18]", "ldr\tx16, [x27, #0x28]", "ldr\tx16, [x27, #0x30]", "blr\tx2",
                 "ldr\tx1, [x27, #0x20]", "add\tx16, x27, #0x1, lsl #12", "ldr\tx16, [x16, #0x10]",
                 "ldr\tx16, [x27, #0x38]", "blr\tx2", 'ret', "ldr\tx16, [x27, #0x68]", "blr\tx2"],
      0x1200 => ["ldr\tx8, [x27, #0x40]", 'ret'],
      0x1300 => ["ldr\tx8, [x27, #0x48]", "cmp\tw1, w22", "ldr\tx8, [x27, #0x40]", 'ret'],
      0x2000 => ["ldr\tx1, [x27, #0x50]", "bl\t0x9000", 'ret'],
      0x2100 => ["ldr\tx1, [x27, #0x58]", "ldr\tx16, [x27, #0x60]", "ldr\tx16, [x27, #0x68]", "blr\tx2", 'ret'],
      0x2200 => ["ldr\tx8, [x27, #0x70]", 'ret'],
      0x3000 => ["ldr\tx2, [x27, #0x78]", "blr\tx30", "ldr\tx1, [x27, #0x80]"] }
  end

  after { FileUtils.remove_entry(directory) }

  it 'reads a checked fromJson, a key whose closure casts to a nullable type being optional' do
    expect(classes['CameraMetadataResponse']['fields'])
      .to eq('name' => { 'type' => 'String', 'required' => true },
             'archetype' => { 'type' => 'String', 'required' => false })
  end

  it 'reads a table of a checked class, and the class it holds', :aggregate_failures do
    expect(classes['CameraServiceResponse']['fields']['camera'])
      .to eq('type' => { 'map' => { 'class' => 'CameraCameraServiceResponse' } }, 'required' => false)
    expect(classes['CameraCameraServiceResponse']['fields'])
      .to eq('enabled' => { 'type' => 'Boolean', 'required' => false })
  end

  it 'stops at the end of the closure' do
    expect(classes['CameraMetadataResponse']['fields'].keys).to eq(%w[name archetype])
  end
end
