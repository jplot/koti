# frozen_string_literal: true

module Schema
  module Extract
    # The Dart snapshot of the Hue app as blutter prints it: its functions from the listings in asm/, the objects of
    # its pool from pp.txt, and their code through a disassembler.
    class Snapshot
      Function = Data.define(:name, :size)

      CLASS = /\A(?:abstract )?class (\S+) extends/
      SIGNATURE = /\A  (\S.*)\{\s*\z/
      ADDRESS = %r{// \*\* addr: (0x\h+), size: (0x\h+)}
      POOL = /\A\[pp\+(0x\h+)\] (.*)/

      # @param directory [String] blutter's output
      # @param disassembler [#call] gives the instructions at an address, for a size in bytes
      def initialize(directory, disassembler)
        @directory = directory
        @disassembler = disassembler
        @functions = {}
        Dir[File.join(directory, 'asm', '**', '*.dart')].each { read(it) }
        @starts = @functions.keys.sort
      end

      # @return [Array(Integer, Integer), nil] address and size of the largest function of that name
      def function(name)
        address, function = @functions.select { |_, f| f.name == name }.max_by { |_, f| f.size }
        [address, function.size] if address
      end

      # The address right after a function counts as its own: blutter lists some fromJson as a 24-byte stub calling a
      # body it leaves out, laid there (+IdentifyFeatureAdded+'s, called from +DeviceAdded+'s).
      #
      # @return [String, nil] +Class.method+ of the function holding the address
      def owner(address)
        index = @starts.bsearch_index { it > address } || @starts.size
        start = @starts[index - 1] if index.positive?
        @functions[start].name if start && address <= start + @functions[start].size
      end

      def object(offset) = (@pool ||= read_pool)[offset]

      def string(offset) = object(offset).to_s[/\AString: "(.*)"\z/, 1]

      def instructions(address, size) = @disassembler.call(address, size)

      def source(library) = File.join(@directory, 'asm', library)

      private

      def read(listing)
        owner = signature = nil
        File.foreach(listing) do |line|
          owner = line[CLASS, 1] || owner
          signature = line[SIGNATURE, 1] || signature unless line.include?('//')
          address, size = line.match(ADDRESS)&.captures
          @functions[address.hex] = Function.new("#{owner}.#{signature[/(\S+)\(/, 1]}", size.hex) if address
        end
      end

      def read_pool
        File.foreach(File.join(@directory, 'pp.txt')).each_with_object({}) do |line, pool|
          pool[Regexp.last_match(1).hex] = Regexp.last_match(2) if line =~ POOL
        end
      end
    end

    Objdump = Data.define(:command, :library) do
      def call(address, size)
        range = ["--start-address=0x#{address.to_s(16)}", "--stop-address=0x#{(address + size).to_s(16)}"]
        listing = IO.popen([command, '-D', '--no-show-raw-insn', '--triple=aarch64', *range, library], &:read)
        raise "#{command} failed on #{library}" unless Process.last_status.success?

        listing.lines.grep(/\A\s+\h+:\s/).map { instruction(it) }
      end

      private

      def instruction(line)
        line.strip.split(/:\s+/, 2).last.sub(/\s*<_kDartSnapshotText\+0x\h+>/, '').sub(%r{\s*//.*}, '').strip
      end
    end
  end
end
