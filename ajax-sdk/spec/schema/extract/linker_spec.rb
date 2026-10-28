# frozen_string_literal: true

require 'google/protobuf/descriptor_pb'
require_relative '../../../schema/extract/linker'

RSpec.describe Schema::Extract::Linker do
  subject(:linker) do
    disablement = file('dis.proto', 'p.dis', [message('DisableRequest', field('hub_id', 1)), 'DisableResponse',
                                              message('Detail', nested: [message('InnerRequest')])])
    group = file('group.proto', 'p.sec',
                 [message('ArmGroupRequest', field('space_locator', 1), field('ignore_alarms', 2))])
    described_class.new([descriptor, disablement, group], texts)
  end

  def field(name, number) = Google::Protobuf::FieldDescriptorProto.new(name:, number:, type: :TYPE_STRING)

  def message(name, *field, nested: []) = Google::Protobuf::DescriptorProto.new(name:, field:, nested_type: nested)

  def file(name, package, messages)
    message_type = messages.map { it.is_a?(String) ? message(it) : it }
    Google::Protobuf::FileDescriptorProto.encode(
      Google::Protobuf::FileDescriptorProto.new(name:, package:, message_type:)
    )
  end

  let(:descriptor) do
    file('sec.proto', 'p.sec',
         [message('ArmSpaceRequest', field('space_locator', 1), field('ignore_alarms', 2)), 'ArmSpaceResponse',
          message('DisarmSpaceRequest', field('space_locator', 1), nested: [message('InnerRequest')]),
          'DisarmSpaceResponse', message('StatusRequest', field('hub_id', 1)), 'StatusResponse'])
  end
  let(:texts) do
    { 'SecProto' => built(descriptor),
      'tp4' => "int SPACE_LOCATOR_FIELD_NUMBER = 1;\nint IGNORE_ALARMS_FIELD_NUMBER = 2;\n#{descriptor_of('SecProto')}",
      'zz9' => 'int HUB_ID_FIELD_NUMBER = 1;' }
  end

  def built(bytes)
    %(a = internalBuildGeneratedFileFrom(new String[]{"#{bytes.bytes.map { format('\\u%04x', it) }.join}"}, d);)
  end

  def descriptor_of(file) = "public static Descriptors.Descriptor getDescriptor() { return #{file}.a; }"

  it 'pairs an obfuscated class by its field numbers in the file its descriptor names, a sibling file aside' do
    expect(linker.pair('p.sec.SpaceSecurityService', 'arm', 'tp4', 'ArmSpaceResponse'))
      .to eq(%w[p.sec.ArmSpaceRequest p.sec.ArmSpaceResponse])
  end

  def about(version)
    file("#{version}.proto", "p.#{version}", [message('GetAboutRequest', field('hub_id', 1)),
                                              message('GetAboutResponse', field("#{version}_only", 1))])
  end

  def about_texts
    texts = %w[v2 v3].each_with_object({}) do |version, all|
      all["p.#{version}.AboutProto"] = built(about(version))
      all["p.#{version}.GetAboutResponse"] = "package p.#{version};\nint #{version.upcase}_ONLY_FIELD_NUMBER = 1;\n" \
                                             "#{descriptor_of('AboutProto')}"
    end
    texts.merge('defpackage.k9' => "package defpackage;\nimport p.v3.AboutProto;\nint HUB_ID_FIELD_NUMBER = 1;\n" \
                                   "#{descriptor_of('AboutProto')}")
  end

  it 'finds the descriptor of a class through its imports or package, a class of the same name aside' do
    linker = described_class.new([about('v2'), about('v3')], about_texts)
    expect(linker.pair('p.svc.AboutService', 'execute', 'defpackage.k9', 'p.v3.GetAboutResponse'))
      .to eq(%w[p.v3.GetAboutRequest p.v3.GetAboutResponse])
  end

  it 'pairs a class without descriptor by its field numbers in the service package' do
    expect(linker.pair('p.sec.HubService', 'check', 'zz9', 'StatusResponse'))
      .to eq(%w[p.sec.StatusRequest p.sec.StatusResponse])
  end

  it 'pairs a method without readable classes by its name, then by the service name' do
    expect([linker.pair('p.sec.ArmSpaceService', 'status', nil, nil),
            linker.pair('p.sec.StatusService', 'run', nil, nil)])
      .to eq([%w[p.sec.StatusRequest p.sec.StatusResponse]] * 2)
  end

  it 'pairs a method by its classes before its name' do
    names = file('x.proto', 'p.x', ['ArmRequest', 'ArmResponse', message('ArmSpaceRequest', field('id', 1)),
                                    'ArmSpaceResponse'])
    linker = described_class.new([names], 'c1' => 'int ID_FIELD_NUMBER = 1;')
    expect(linker.pair('p.x.XService', 'arm', 'c1', 'ArmSpaceResponse'))
      .to eq(%w[p.x.ArmSpaceRequest p.x.ArmSpaceResponse])
  end

  it 'does not pair a class without field numbers with a message without fields' do
    lone = file('y.proto', 'p.y', [message('OnlyRequest', field('id', 1)), 'EmptyResponse'])
    expect(described_class.new([lone], 'e1' => 'class e1 {}').pair('p.y.YService', 'run', 'e1', nil))
      .to eq(%w[p.y.OnlyRequest p.y.EmptyResponse])
  end

  it 'pairs a method by the lone request and response of its package, nested ones aside' do
    expect(linker.pair('p.dis.DeviceCommandDisablementService', 'run', nil, nil))
      .to eq(%w[p.dis.DisableRequest p.dis.DisableResponse])
  end

  it 'leaves a class unpaired when several messages of the file its descriptor names have its field numbers' do
    twin = file('twin.proto', 'p.twin', [message('ARequest', field('id', 1)), message('BRequest', field('id', 1)),
                                         'AResponse'])
    texts = { 'TwinProto' => built(twin), 'xx1' => "int ID_FIELD_NUMBER = 1;\n#{descriptor_of('TwinProto')}" }
    expect(described_class.new([twin], texts).pair('p.twin.TwinService', 'run', 'xx1', 'AResponse')).to be_nil
  end

  it 'pairs a class without fields with the top-level message of its file, a nested one aside' do
    stream = file('stream.proto', 'p.user',
                  ['StreamRequest', message('StreamResponse', field('space', 1), nested: [message('Failure')])])
    texts = { 'StreamProto' => built(stream), 'zq1' => "class zq1 {}\n#{descriptor_of('StreamProto')}",
              'zq2' => "int SPACE_FIELD_NUMBER = 1;\n#{descriptor_of('StreamProto')}" }
    expect(described_class.new([stream], texts).pair('p.space.SpaceService', 'streamUserSpaces', 'zq1', 'zq2'))
      .to eq(%w[p.user.StreamRequest p.user.StreamResponse])
  end

  it 'leaves a method unpaired when its package holds several requests and no name matches' do
    expect(linker.pair('p.sec.OtherService', 'run', nil, nil)).to be_nil
  end

  it 'reads the field numbers of a message class, normalized, without those of its nested classes' do
    text = "int SPACE_LOCATOR_FIELD_NUMBER = 1;\npublic static final class Inner {\nint INNER_FIELD_NUMBER = 3;"
    expect(described_class.field_numbers(text)).to eq('spacelocator' => 1)
  end
end
