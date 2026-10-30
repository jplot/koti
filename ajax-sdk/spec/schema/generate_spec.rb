# frozen_string_literal: true

require 'tmpdir'
require 'zlib'
require_relative '../../schema/generate'

RSpec.describe Schema::Generate do
  let(:root) { Dir.mktmpdir }

  before do
    schemas = File.join(root, 'lib/ajax/sdk/cloud/schemas')
    FileUtils.mkdir_p(schemas)
    set = Google::Protobuf::FileDescriptorSet.new(file: [ProbeSchema.file])
    Zlib::GzipWriter.open(File.join(schemas, 'descriptors.pb.gz')) { it.write(Google::Protobuf::FileDescriptorSet.encode(set)) }
    File.write(File.join(schemas, 'methods.tsv'), "/probe.S/m\tunary\tprobe.Probe\tprobe.Probe\n")
    described_class.write(root)
  end

  after { FileUtils.remove_entry(root) }

  it 'finds nothing to change right after writing' do
    expect(described_class.check(root)).to be_empty
  end

  it 'reports a file edited by hand' do
    File.write(File.join(root, 'lib/ajax/sdk/cloud/messages/probe.rb'), "# edited\n", mode: 'a')
    expect(described_class.check(root)).to eq(['lib/ajax/sdk/cloud/messages/probe.rb'])
  end

  it 'reports the named methods edited by hand' do
    File.write(File.join(root, 'lib/ajax/sdk/cloud/methods.rb'), "# edited\n", mode: 'a')
    expect(described_class.check(root)).to eq(['lib/ajax/sdk/cloud/methods.rb'])
  end

  it 'reports a file left over' do
    File.write(File.join(root, 'sig/ajax/sdk/cloud/messages/old.rbs'), '')
    expect(described_class.check(root)).to eq(['sig/ajax/sdk/cloud/messages/old.rbs'])
  end
end
