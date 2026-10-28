# frozen_string_literal: true

require 'tmpdir'
require 'zlib'
require 'google/protobuf/descriptor_pb'
require_relative '../../../schema/extract/schemas'

RSpec.describe Schema::Extract::Schemas do
  let(:directory) { Dir.mktmpdir }
  let(:descriptor) do
    field = Google::Protobuf::FieldDescriptorProto.new(name: 'space_locator', number: 1, type: :TYPE_STRING)
    message_type = [Google::Protobuf::DescriptorProto.new(name: 'ArmSpaceRequest', field: [field]),
                    *%w[ArmSpaceResponse DisarmSpaceRequest].map { Google::Protobuf::DescriptorProto.new(name: it) }]
    Google::Protobuf::FileDescriptorProto.encode(
      Google::Protobuf::FileDescriptorProto.new(name: 'sec.proto', package: 'p.sec', message_type:)
    )
  end

  before do
    source = File.join(directory, 'sources')
    FileUtils.mkdir_p(source)
    literal = descriptor.bytes.map { format('\\u%04x', it) }.join
    File.write("#{source}/SecProto.java", %(a = internalBuildGeneratedFileFrom(new String[]{"#{literal}"}, deps);))
    File.write("#{source}/SpaceSecurityServiceGrpcKt.java", <<~JAVA)
      import defpackage.tp4;
      final class SpaceSecurityServiceGrpcKt {
      String SERVICE_NAME = "p.sec.SpaceSecurityService";
      }
    JAVA
    File.write("#{source}/tp4.java", "int SPACE_LOCATOR_FIELD_NUMBER = 1;\n" \
                                     'public static Descriptors.Descriptor getDescriptor() { return SecProto.a; }')
    File.write("#{source}/stub.java", <<~JAVA)
      v.e = x.a;
      v.a = y.a(SpaceSecurityServiceGrpcKt.SERVICE_NAME, "arm");
      tp4 defaultInstance = tp4.getDefaultInstance();
      v.d = new z(ArmSpaceResponse.getDefaultInstance());
      w.e = x.a;
      w.a = y.a(SpaceSecurityServiceGrpcKt.SERVICE_NAME, "lost");
    JAVA
  end

  after { FileUtils.remove_entry(directory) }

  def rebuild = described_class.write([File.join(directory, 'sources')], directory)

  it 'writes each method it pairs, with its call type, request and response', :aggregate_failures do
    expect { rebuild }.to output("unpaired\tp.sec.SpaceSecurityService\tlost\n").to_stderr
    expect(File.read(File.join(directory, 'methods.tsv')))
      .to eq("/p.sec.SpaceSecurityService/arm\tunary\tp.sec.ArmSpaceRequest\tp.sec.ArmSpaceResponse\n")
  end

  it 'writes a descriptor once, though several jadx runs hold it', :aggregate_failures do
    sources = File.join(directory, 'sources')
    expect { described_class.write([sources, sources], directory) }.to output.to_stderr
    gzip = File.binread(File.join(directory, 'descriptors.pb.gz'))
    expect(Google::Protobuf::FileDescriptorSet.decode(Zlib.gunzip(gzip)).file.size).to eq(1)
  end

  it 'writes nothing when a descriptor cannot be read', :aggregate_failures do
    File.write(File.join(directory, 'sources', 'Bad.java'),
               %(b = internalBuildGeneratedFileFrom(new String[]{"\\u00ff"}, d);))
    expect { rebuild }.to raise_error(Google::Protobuf::ParseError)
    expect(Dir.children(directory)).to eq(['sources'])
  end

  it 'writes the length of each descriptor as a protobuf varint' do
    expect([127, 200, 300].map { described_class.varint(it) }).to eq(["\x7F".b, "\xC8\x01".b, "\xAC\x02".b])
  end

  it 'counts the methods it paired', :aggregate_failures do
    expect { expect(rebuild).to eq(1) }.to output.to_stderr
  end

  it 'writes the descriptors of the app as one gzipped FileDescriptorSet, bytes as they are', :aggregate_failures do
    expect { rebuild }.to output.to_stderr
    gzip = File.binread(File.join(directory, 'descriptors.pb.gz'))
    set = Google::Protobuf::FileDescriptorSet.decode(Zlib.gunzip(gzip))
    expect(set.file.map { Google::Protobuf::FileDescriptorProto.encode(it) }).to eq([descriptor])
  end
end
