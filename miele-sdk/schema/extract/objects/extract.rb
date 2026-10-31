# frozen_string_literal: true

# Usage: ruby schema/extract/objects/extract.rb path/to/il schema/addresses.tsv lib/miele/sdk/objects/objects.json.gz
# where path/to/il holds the ikdasm output of the app's Miele.*ApplianceCommunication* assemblies.

require 'json'
require 'zlib'
require_relative 'il_model'
require_relative 'layouts'
require_relative 'addresses'

module Schema
  module Extract
    # The DOP2 and Dop1 objects of the Miele app, read from the IL ikdasm prints for its assemblies.
    module Objects
      FAMILIES = {
        'Miele.Modules.Oven.ApplianceCommunication.Protocols' => 'oven',
        'Miele.Modules.Hoods.ApplianceCommunication.ApplianceData' => 'hood',
        'Miele.Modules.Hobs.ApplianceCommunication.ApplianceData' => 'hob',
        'Miele.Modules.Dishwasher.ApplianceCommunication.ApplianceData' => 'dishwasher',
        'Miele.Modules.LaundryCare.ApplianceCommunication.ApplianceData' => 'laundry',
        'Miele.Modules.SDA.CoffeeMaker.ApplianceCommunication.ApplianceData' => 'coffee',
        'Miele.Modules.Drawers.ApplianceCommunication.ApplianceData' => 'drawer'
      }.freeze

      NAME = %r{Miele\.[\w.]+(?:/\w+)*}

      # @param paths [Array<String>] +.il+ files
      # @param table [String] where the app reads or writes each top-level DOP2 class, one address per line: family,
      #   name, unit, attribute, then idx1 and idx2 unless it sends no index (+-+ for one it computes); its classes
      #   count as used
      # @return [Array(Hash, Array<String>)] +dop2+, +dop1+ and +enums+, each a list with the family and the short
      #   name of each entry; then where the call-site rules disagree with the table
      def self.extract(paths, table) = Extraction.new(paths.flat_map { IlModel.parse(it) }, table).result

      # @return [String, nil] the family of an object class, nil outside the families
      def self.family(name, entry)
        family = FAMILIES[entry['assembly']] or return
        return family unless family == 'coffee'

        name.include?('.Cm7.') ? 'coffee_cm7' : 'coffee_gen7'
      end

      # @return [String] the name inside its family: a nested class keeps its outer one
      def self.short(name) = name.split('.').last.sub(%r{\AEnums/}, '')

      # One extraction over the classes of a set of assemblies.
      class Extraction
        # @param classes [Array<IlModel::Klass>]
        # @param table [String] the path of the address table
        def initialize(classes, table)
          @classes = classes
          layouts = Layouts.new(classes)
          @enums = layouts.enums
          @dop2 = layouts.dop2.select { |name, entry| Objects.family(name, entry) }
          @dop1 = layouts.dop1.select { |name, entry| Objects.family(name, entry) }
          @addresses = read_table(table)
        end

        # @return [Array(Hash, Array<String>)]
        def result
          dop2 = used_dop2
          dop1 = @dop1.select { |name, _| cited.include?(name.split('/').first) }
          [output(dop2, dop1), disagreements(Addresses.new(@classes, @dop2).find.slice(*dop2.keys))]
        end

        private

        def cited
          @cited ||= @classes.select { it.assembly.end_with?('.ApplianceCommunication.Implementation') }
                             .flat_map { |klass| klass.procedures.flat_map(&:body) + [klass.extends.to_s] }
                             .flat_map { it.gsub(/\[[^\]]*\]/, '').scan(NAME) }.to_set
        end

        def used_dop2
          names = closure(cited.select { @dop2.key?(it) } | @addresses.keys)
          names.to_h { [it, @dop2.fetch(it).merge('addresses' => @addresses.fetch(it, []))] }
        end

        def closure(start)
          seen = start.to_set
          queue = start.to_a
          while (name = queue.shift)
            held(name).each { queue << it if seen.add?(it) }
          end
          seen.to_a
        end

        def held(name)
          types = @dop2.fetch(name)['fields'].filter_map { it['type'] if it['kind'].start_with?('struct') }
          types.select { @dop2.key?(it) }
        end

        def read_table(path)
          lines = File.readlines(path, chomp: true).reject { it.empty? || it.start_with?('#') }
          rows = lines.map { row(path, *it.sub(/\s*#.*\z/, '').split("\t")) }
          rows.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
        end

        def row(path, family, name, *numbers)
          [full_name(path, family, name), numbers.map { it == '-' ? nil : Integer(it) }]
        end

        def full_name(path, family, name)
          @by_short ||= @dop2.keys.group_by { "#{Objects.family(it, @dop2[it])}\t#{Objects.short(it)}" }
          @by_short.fetch("#{family}\t#{name}") { raise ArgumentError, "#{path}: no class #{family} #{name}" }.first
        end

        def disagreements(found)
          found.filter_map do |name, addresses|
            missing = addresses.reject { |address| @addresses.fetch(name, []).any? { covers?(it, address) } }
            next if missing.empty?

            "#{Objects.family(name, @dop2[name])} #{Objects.short(name)}: the call sites give #{missing.inspect}, " \
              "the table #{@addresses.fetch(name, []).inspect}"
          end
        end

        # An index the app computes (nil in the table) covers any value a call site gives.
        def covers?(row, address)
          row.size == address.size && row.zip(address).all? { |want, got| want.nil? || want == got }
        end

        def output(dop2, dop1)
          enums = @enums.slice(*(dop2.values + dop1.values).flat_map { |entry| entry['fields'].map { it['type'] } })
          names = distinct(dop2.merge(dop1, enums))
          { 'dop2' => dop2, 'dop1' => dop1, 'enums' => enums }.transform_values do |entries|
            entries.map { |name, entry| entry_of(name, entry, names) }
          end
        end

        # The short name of each class, prefixed with the namespace that tells it apart where two share one in a
        # family: the laundry module has a washer (+WA+) and a dryer (+TD+) copy of some Dop1 enums.
        def distinct(entries)
          groups = entries.keys.group_by { "#{Objects.family(it, entries[it])} #{Objects.short(it)}" }
          groups.values.flat_map do |names|
            next [[names.first, Objects.short(names.first)]] if names.one?

            names.map { [it, "#{it.split('.')[-2]}_#{Objects.short(it)}"] }
          end.to_h
        end

        def entry_of(name, entry, names)
          renamed = entry.except('assembly')
          %w[fields sections arrays].each do |key|
            renamed[key] &&= renamed[key].map { it.merge('type' => names.fetch(it['type'], it['type'])) }
          end
          { 'family' => Objects.family(name, entry), 'name' => names.fetch(name), **renamed }
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  directory, table, target = ARGV
  data, disagreements = Schema::Extract::Objects.extract(Dir[File.join(directory, '*.il')], table)
  Zlib::GzipWriter.open(target) { it.write(JSON.generate(data)) }
  warn "dop2 #{data['dop2'].size}, dop1 #{data['dop1'].size}, enums #{data['enums'].size}"
  warn disagreements
end
