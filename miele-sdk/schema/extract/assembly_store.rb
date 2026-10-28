# frozen_string_literal: true

# Usage: ruby schema/extract/assembly_store.rb path/to/libassemblies.arm64-v8a.blob.so path/to/dlls

require 'fileutils'

module Schema
  module Extract
    # The .NET assemblies of the Miele app, packed by .NET for Android into one store (version 2, magic +XABA+), each
    # LZ4-compressed behind an +XALZ+ header.
    class AssemblyStore
      DESCRIPTOR = 28

      # @param store [String] the content of libassemblies.arm64-v8a.blob.so
      def self.unpack(store, directory)
        new(store).each do |name, assembly|
          path = File.join(directory, name)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, assembly)
        end
      end

      def initialize(store)
        @store = store.b
        @base = @store.index('XABA')
        _, version, @count, _, index_size = @store.byteslice(@base, 20).unpack('a4V4')
        raise ArgumentError, "assembly store version #{version & 0xff}, not 2" unless (version & 0xff) == 2

        @descriptors = @base + 20 + index_size
      end

      def each
        names = @descriptors + (@count * DESCRIPTOR)
        @count.times do |index|
          name = @store.byteslice(names + 4, @store.byteslice(names, 4).unpack1('V'))
          yield name, assembly(index)
          names += 4 + name.bytesize
        end
      end

      private

      def assembly(index)
        _, offset, size = @store.byteslice(@descriptors + (index * DESCRIPTOR), 12).unpack('V3')
        entry = @store.byteslice(@base + offset, size)
        entry.start_with?('XALZ') ? Lz4.new(entry.byteslice(12..), entry.byteslice(8, 4).unpack1('V')).decode : entry
      end
    end

    # An LZ4 block, the format .NET for Android compresses each assembly of the store with.
    class Lz4
      def initialize(source, size)
        @source = source
        @size = size
        @cursor = 0
        @output = String.new(capacity: size, encoding: Encoding::BINARY)
      end

      def decode
        while @output.bytesize < @size
          token = byte
          literals(length(token >> 4))
          break if @output.bytesize >= @size

          match(token & 15)
        end
        @output
      end

      private

      def byte = @source.getbyte(@cursor).tap { @cursor += 1 }

      def literals(count)
        @output << @source.byteslice(@cursor, count)
        @cursor += count
      end

      # A match copies byte by byte what it may itself be writing, from an offset read before its length.
      def match(nibble)
        start = @output.bytesize - (byte | (byte << 8))
        (length(nibble) + 4).times { @output << @output.getbyte(start + it) }
      end

      def length(length)
        return length unless length == 15

        loop do
          more = byte
          length += more
          return length unless more == 255
        end
      end
    end
  end
end

Schema::Extract::AssemblyStore.unpack(File.binread(ARGV.fetch(0)), ARGV.fetch(1)) if $PROGRAM_NAME == __FILE__
