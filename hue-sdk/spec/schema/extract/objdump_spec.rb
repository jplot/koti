# frozen_string_literal: true

require_relative '../../../schema/extract/snapshot'

RSpec.describe Schema::Extract::Objdump do
  subject(:objdump) { described_class.new(command: File.join(directory, 'llvm-objdump'), library: 'libapp.so') }

  let(:directory) { Dir.mktmpdir }

  before do
    File.write(File.join(directory, 'llvm-objdump'), <<~SH, perm: 0o755)
      #!/bin/sh
      echo "$@" > "#{directory}/arguments"
      cat <<'OUT'
      libapp.so:	file format elf64-littleaarch64

      Disassembly of section .text:

      0000000001310000 <_kDartSnapshotText>:
       14e4f80:      	add	x2, x27, #0x16, lsl #12 // =0x16000
       14e5000:      	bl	0x13302cc <_kDartSnapshotText+0x202cc>
      OUT
    SH
  end

  after { FileUtils.remove_entry(directory) }

  it 'reads the instructions without their address, symbol or comment' do
    expect(objdump.call(0x14e4f80, 0x84)).to eq(["add\tx2, x27, #0x16, lsl #12", "bl\t0x13302cc"])
  end

  it 'disassembles the range asked for' do
    objdump.call(0x14e4f80, 0x84)
    expect(File.read(File.join(directory, 'arguments')))
      .to include('--start-address=0x14e4f80 --stop-address=0x14e5004 libapp.so')
  end

  context 'when llvm-objdump fails' do
    before { File.write(File.join(directory, 'llvm-objdump'), "#!/bin/sh\nexit 1\n", perm: 0o755) }

    it 'raises instead of reading no instruction' do
      expect { objdump.call(0x14e4f80, 0x84) }.to raise_error(RuntimeError, /llvm-objdump failed on libapp\.so/)
    end
  end
end
