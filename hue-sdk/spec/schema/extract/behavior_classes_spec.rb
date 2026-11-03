# frozen_string_literal: true

require_relative '../../../schema/extract/behaviors'

RSpec.describe Schema::Extract::BehaviorClasses do
  subject(:classes) { reader.read(%w[BridgeBehaviorWhen BridgeBehaviorMetadata]) }

  let(:reader) { described_class.new(snapshot, taken: ['BehaviorInstance']) }
  let(:snapshot) { Schema::Extract::Snapshot.new(directory, ->(address, _) { code.fetch(address) }) }
  let(:directory) do
    blutter_output('asm/behavior_bridge_control/src/bridge/bridge_step_result.dart' => <<~DART, 'pp.txt' => <<~POOL)
      class :: {
        static _ _$BridgeBehaviorWhenFromJson(/* No info */) {
          // ** addr: 0x100, size: 0x40
        }
        static _ _$BridgeBehaviorMetadataFromJson(/* No info */) {
          // ** addr: 0x200, size: 0x40
        }
        static _ _$BridgeBehaviorTimePointFromJson(/* No info */) {
          // ** addr: 0x300, size: 0x40
        }
        static _ _$TimeSpanFromJson(/* No info */) {
          // ** addr: 0x400, size: 0x40
        }
        static _ _$BridgeBehaviorUnusedFromJson(/* No info */) {
          // ** addr: 0x500, size: 0x40
        }
        static _ _$BridgeBehaviorInstanceFromJson(/* No info */) {
          // ** addr: 0x600, size: 0x40
        }
        static _ _$BridgeAccessoryConfigFromJson(/* No info */) {
          // ** addr: 0xa00, size: 0x40
        }
        static _ $enumDecode(/* No info */) {
          // ** addr: 0x800, size: 0x40
        }
        static Y0? $enumDecodeNullable<Y0 extends Enum, Y1>(Map<Y0, Y1>, Object?) {
          // ** addr: 0x900, size: 0x40
        }
      }
      class BridgeAccessoryHandWritten extends Object {
        factory _ BridgeAccessoryHandWritten.fromJson(/* No info */) {
          // ** addr: 0xb00, size: 0x40
        }
      }
      class BridgeAccessoryActionValue extends Object {
        static _ fromJsonActionValues(/* No info */) {
          // ** addr: 0xc00, size: 0x40
        }
      }
    DART
      [pp+0x10] String: "time_point"
      [pp+0x18] Type: Map<String, dynamic>
      [pp+0x20] String: "recurrence_days"
      [pp+0x28] Type: List?
      [pp+0x30] TypeArguments: <Weekday>
      [pp+0x38] String: "randomization"
      [pp+0x40] String: "type"
      [pp+0x48] TypeArguments: <Kind, String>
      [pp+0x50] Map<Kind, String>(2) {
        Obj!Kind@1: "time",
        Obj!Kind@2: "sunset"
      }
      [pp+0x58] String: "name"
      [pp+0x60] Type: String?
      [pp+0x68] String: "rid"
      [pp+0x70] Type: String
      [pp+0x78] String: "hours"
      [pp+0x80] Type: num?
      [pp+0x88] Map<Weekday, String>(2) {
        Obj!Weekday@1: "monday",
        Obj!Weekday@2: "tuesday"
      }
      [pp+0x90] String: "mode"
      [pp+0x98] String: "buttons"
      [pp+0xa0] Type: Map<String, dynamic>?
      [pp+0xa8] TypeArguments: <String, BridgeBehaviorMetadata>
      [pp+0xb0] String: "signal"
      [pp+0xb8] TypeArguments: <Object, TimeSpan>
      [pp+0xc0] String: "recall_single"
      [pp+0xc8] String: "chime"
    POOL
  end
  let(:code) do
    { 0x100 => ["ldr\tx2, [x27, #0x10]", "blr\tx30", "ldr\tx1, [x27, #0x18]", "bl\t0x300",
                "ldr\tx2, [x27, #0x20]", "blr\tx30", "ldr\tx1, [x27, #0x28]", "ldr\tx3, [x27, #0x30]",
                "ldr\tx2, [x27, #0x38]", "blr\tx30", "ldr\tx2, [x27, #0x38]", "blr\tx30", "ldr\tx1, [x27, #0x18]",
                "bl\t0x400"],
      0x200 => ["ldr\tx2, [x27, #0x58]", "blr\tx30", "ldr\tx1, [x27, #0x60]",
                "ldr\tx2, [x27, #0x68]", "blr\tx30", "ldr\tx1, [x27, #0x70]",
                "ldr\tx2, [x27, #0x90]", "blr\tx30", "ldr\tx1, [x27, #0x48]", "ldr\tx1, [x27, #0x50]", "bl\t0x900"],
      0x300 => ["ldr\tx2, [x27, #0x40]", "blr\tx30", "ldr\tx1, [x27, #0x48]", "ldr\tx1, [x27, #0x50]", "bl\t0x800"],
      0x400 => ["ldr\tx2, [x27, #0x78]", "blr\tx30", "ldr\tx1, [x27, #0x80]"],
      0x600 => [],
      0xa00 => ["ldr\tx2, [x27, #0x98]", "blr\tx30", "ldr\tx1, [x27, #0xa0]", "ldr\tx3, [x27, #0xa8]",
                "ldr\tx2, [x27, #0xb0]", "blr\tx30", "ldr\tx3, [x27, #0xb8]",
                "ldr\tx2, [x27, #0xc0]", "blr\tx30", "bl\t0xc00", "ldr\tx2, [x27, #0xc8]", "blr\tx30"],
      0xb00 => ["ldr\tx2, [x27, #0x68]", "blr\tx30", "ldr\tx1, [x27, #0x70]"] }
  end

  after { FileUtils.remove_entry(directory) }

  it 'types a nested class, required when its key is read once' do
    expect(classes['BehaviorWhen']['fields']['time_point'])
      .to eq('type' => { 'class' => 'BehaviorTimePoint' }, 'required' => true)
  end

  it 'leaves optional a key read twice, for its null check' do
    expect(classes['BehaviorWhen']['fields']['randomization'])
      .to eq('type' => { 'class' => 'TimeSpan' }, 'required' => false)
  end

  it 'types an enum as a string with its values, required when decoded without Nullable', :aggregate_failures do
    expect(classes['BehaviorTimePoint']['fields']['type'])
      .to eq('type' => 'String', 'required' => true, 'values' => %w[time sunset])
    expect(classes['BehaviorMetadata']['fields']['mode'])
      .to eq('type' => 'String', 'required' => false, 'values' => %w[time sunset])
  end

  it 'types a list of an enum as a list of strings with its values' do
    expect(classes['BehaviorWhen']['fields']['recurrence_days'])
      .to eq('type' => { 'list' => 'String' }, 'required' => false, 'values' => %w[monday tuesday])
  end

  it 'requires a primitive decoded without a question mark, not one with it', :aggregate_failures do
    expect(classes['BehaviorMetadata']['fields']['rid']).to eq('type' => 'String', 'required' => true)
    expect(classes['BehaviorMetadata']['fields']['name']).to eq('type' => 'String', 'required' => false)
  end

  it 'drops the Bridge prefix and keeps the app class as origin' do
    expect(classes['BehaviorWhen']).to include('origin' => 'BridgeBehaviorWhen', 'kind' => 'behavior')
  end

  it 'reads the classes the roots reach, and only them', :aggregate_failures do
    expect(classes.keys).to contain_exactly('BehaviorWhen', 'BehaviorMetadata', 'BehaviorTimePoint', 'TimeSpan')
  end

  context 'with the classes of an accessory' do
    subject(:fields) { reader.read(['BridgeAccessoryConfig'])['AccessoryConfig']['fields'] }

    it 'types a table of values, by the type arguments of its map' do
      expect(fields['buttons']).to eq('type' => { 'map' => { 'class' => 'BehaviorMetadata' } }, 'required' => false)
    end

    it 'types the value of a converter with a closure, by its type arguments' do
      expect(fields['signal']).to eq('type' => { 'class' => 'TimeSpan' }, 'required' => false)
    end

    it 'types the value of a hand-written converter of the app, always optional' do
      expect(fields['recall_single'])
        .to eq('type' => { 'list' => { 'class' => 'AccessoryActionValue' } }, 'required' => false)
    end

    it 'leaves out the default of a key, which the app loads like a key' do
      expect(fields).not_to have_key('chime')
    end

    it 'reads a class from its hand-written fromJson' do
      expect(reader.read(['BridgeAccessoryHandWritten'])['AccessoryHandWritten']['fields'].keys).to eq(['rid'])
    end
  end

  it 'stops on a name hue.json already takes' do
    taken = described_class.new(snapshot, taken: ['BehaviorWhen'])
    expect { taken.read(['BridgeBehaviorWhen']) }.to raise_error(ArgumentError, /BehaviorWhen/)
  end

  it 'renames a class whose plain name hue.json takes' do
    expect(reader.read(['BridgeBehaviorInstance'])).to have_key('BehaviorInstanceReference')
  end

  it 'stops on a class the app has no fromJson for' do
    expect { reader.read(['BridgeBehaviorMissing']) }.to raise_error(ArgumentError, /BridgeBehaviorMissing/)
  end
end
