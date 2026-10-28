# frozen_string_literal: true

module Schema
  module Extract
    # The SIA event codes of pysiaalarm, read from its sia_codes.py as text, never run: each code with the label of its
    # type.
    module SiaCodes
      ENTRY = /^\s+"([^"]+)": SIACode\(/
      CODE = /^\s+"([A-Z]{2})": SIACode\(\s+code="\1",\s+type="([^"\\\t\n]+)",\s+description=/

      module_function

      # @raise [ArgumentError] when no code reads, or one does not read as the others, rather than leave it out
      def rows(source)
        entries = source.scan(ENTRY)
        rows = source.scan(CODE)
        raise ArgumentError, "read #{rows.size} of #{entries.size} codes" if rows.empty? || rows.size != entries.size

        rows
      end

      def write(source, path) = File.write(path, rows(File.read(source)).map { "#{it.join("\t")}\n" }.join)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby schema/extract/sia_codes.rb path/to/sia_codes.py lib/ajax/sdk/sia/codes.tsv' unless ARGV.size == 2
  Schema::Extract::SiaCodes.write(*ARGV)
end
