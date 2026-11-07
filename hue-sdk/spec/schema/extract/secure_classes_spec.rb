# frozen_string_literal: true

require_relative '../../../schema/extract/secure'

RSpec.describe Schema::Extract::SecureClasses do
  subject(:classes) { reader.read(%w[ArmDisarmStateResponse ArmDisarmModeConfigRequest]) }

  let(:reader) { described_class.new(snapshot, taken: []) }
  let(:snapshot) { Schema::Extract::Snapshot.new(directory, ->(address, _) { code.fetch(address) }) }
  let(:directory) do
    blutter_output('asm/arm_disarm_client/src/api/http/response.dart' => <<~RESPONSE,
      class :: {
        static _ _$ArmDisarmStateResponseFromJson(/* No info */) {
          // ** addr: 0x100, size: 0x40
        }
        static _ _$ArmDisarmStateSourceResponseFromJson(/* No info */) {
          // ** addr: 0x200, size: 0x40
        }
        static _ _$AlarmSignalFromJson(/* No info */) {
          // ** addr: 0x300, size: 0x40
        }
      }
    RESPONSE
                   'asm/arm_disarm_client/src/api/http/request.dart' => <<~REQUEST, 'pp.txt' => <<~POOL)
                     class ArmDisarmModeConfigRequest extends _$ArmDisarmModeConfigRequest {

                       Map<String, Object?> toJson(ArmDisarmModeConfigRequest) {
                         // ** addr: 0x600, size: 0x48
                       }
                     }
                     class ActivityZoneUpdate extends _$ActivityZoneUpdate {

                       Map<String, Object?> toJson(ActivityZoneUpdate) {
                         // ** addr: 0x900, size: 0x48
                       }
                     }
                     class ArmDisarmGeofenceStatusConfigRequest extends _$ArmDisarmGeofenceStatusConfigRequest {

                       Map<String, Object?> toJson(ArmDisarmGeofenceStatusConfigRequest) {
                         // ** addr: 0x700, size: 0x48
                       }
                     }
                   REQUEST
                     [pp+0x10] String: "arm_state"
                     [pp+0x18] Type: String
                     [pp+0x20] String: "trigger_time"
                     [pp+0x28] String: "source"
                     [pp+0x30] Type: Map<String, dynamic>
                     [pp+0x38] String: "type"
                     [pp+0x40] String: "entry_delay"
                     [pp+0x48] String: "alarm_duration"
                     [pp+0x50] String: "device"
                     [pp+0x58] String: "exit_delay"
                     [pp+0x60] String: "light"
                     [pp+0x68] String: "speaker"
                     [pp+0x70] Type: String?
                     [pp+0x78] String: "enabled"
                   POOL
  end
  let(:code) do
    { 0x100 => ["ldr\tx2, [x27, #0x10]", "blr\tx30", "ldr\tx1, [x27, #0x18]",
                "ldr\tx2, [x27, #0x20]", "blr\tx30", "ldr\tx2, [x27, #0x20]", "blr\tx30", "ldr\tx1, [x27, #0x18]",
                "ldr\tx2, [x27, #0x28]", "blr\tx30", "ldr\tx1, [x27, #0x30]", "bl\t0x200"],
      0x200 => ["ldr\tx2, [x27, #0x38]", "blr\tx30", "ldr\tx1, [x27, #0x18]"],
      0x300 => ["ldr\tx2, [x27, #0x60]", "blr\tx30", "ldr\tx1, [x27, #0x70]",
                "ldr\tx2, [x27, #0x68]", "blr\tx30", "ldr\tx1, [x27, #0x70]"],
      0x600 => %W[bl\t0x800 ret], 0x700 => %W[bl\t0x800 ret], 0x900 => %W[bl\t0xa00 ret],
      0xa00 => [*Array.new(16, "mov\tx29, x15"), "ldr\tx2, [x27, #0x78]", "add\tx3, x22, #0x20", "blr\tx30", 'ret'],
      0x800 => [*Array.new(8, "mov\tx29, x15"),
                "ldur\tx6, [x1, #0xf]", "ldr\tx2, [x27, #0x40]", "blr\tx30",
                "ldur\td0, [x1, #0x23]", "ldr\tx2, [x27, #0x58]", "blr\tx30",
                "ldur\tw3, [x1, #0x17]", "cmp\tw3, w22", "ldr\tx2, [x27, #0x48]", "blr\tx30",
                "ldur\tw4, [x1, #0x1b]", "ldr\tx2, [x27, #0x50]", "blr\tx30", 'ret'] }
  end

  after { FileUtils.remove_entry(directory) }

  it 'reads ArmDisarmStateResponse from its fromJson, and the classes it holds', :aggregate_failures do
    response = classes['ArmDisarmStateResponse']
    expect(response).to include('origin' => 'ArmDisarmStateResponse', 'kind' => 'response')
    expect(response['fields'].transform_values { it['type'] }).to eq(
      'arm_state' => 'String', 'trigger_time' => 'String', 'source' => { 'class' => 'ArmDisarmStateSourceResponse' }
    )
    expect(classes['ArmDisarmStateSourceResponse']['fields'])
      .to eq('type' => { 'type' => 'String', 'required' => true })
  end

  it 'reads a request from its toJson, typing what the field load tells' do
    expect(classes['ArmDisarmModeConfigRequest']).to eq(
      'origin' => 'ArmDisarmModeConfigRequest', 'kind' => 'request',
      'fields' => { 'entry_delay' => { 'type' => 'Integer', 'required' => true },
                    'exit_delay' => { 'type' => 'Numeric', 'required' => true },
                    'alarm_duration' => { 'type' => 'Object', 'required' => false },
                    'device' => { 'type' => 'Object', 'required' => true } }
    )
  end

  it 'tells a required key from an optional one', :aggregate_failures do
    expect(classes['ArmDisarmStateResponse']['fields'].transform_values { it['required'] })
      .to eq('arm_state' => true, 'trigger_time' => false, 'source' => true)
    expect(classes['ArmDisarmModeConfigRequest']['fields'].transform_values { it['required'] })
      .to eq('entry_delay' => true, 'exit_delay' => true, 'alarm_duration' => false, 'device' => true)
  end

  it 'reads a key the toJson always writes as true' do
    expect(reader.read(['ActivityZoneUpdate'])['ActivityZoneUpdate']['fields'])
      .to eq('enabled' => { 'type' => 'Boolean', 'required' => true })
  end

  it 'follows a toJson shared with an identical class' do
    shared = reader.read(['ArmDisarmGeofenceStatusConfigRequest'])['ArmDisarmGeofenceStatusConfigRequest']
    expect(shared['fields']).to eq(classes['ArmDisarmModeConfigRequest']['fields'])
  end

  it 'keeps every key a fromJson reads, those an automation drops included' do
    expect(reader.read(['AlarmSignal'])['AlarmSignal']['fields'])
      .to eq('light' => { 'type' => 'String', 'required' => false },
             'speaker' => { 'type' => 'String', 'required' => false })
  end

  it 'stops on a class the app has neither fromJson nor toJson for' do
    expect { reader.read(['ArmDisarmMissing']) }.to raise_error(ArgumentError, /ArmDisarmMissing/)
  end

  it 'stops on a class another generated file holds' do
    taken = described_class.new(snapshot, taken: ['ArmDisarmStateSourceResponse'])
    expect { taken.read(['ArmDisarmStateResponse']) }.to raise_error(ArgumentError, /ArmDisarmStateSourceResponse/)
  end
end
