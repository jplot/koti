# frozen_string_literal: true

require_relative 'il_model'
require_relative 'dop1_layout'

module Schema
  module Extract
    module Objects
      # The DOP2 and Dop1 object classes among the IL classes, their field layouts, and the enums they use.
      class Layouts
        PROTOCOLS = 'Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols'
        DOP2 = "#{PROTOCOLS}.Dop2.Dop2Object".freeze
        DOP1 = "#{PROTOCOLS}.Dop1.Dop1Object".freeze
        DOP1_ARRAY = "#{PROTOCOLS}.Dop1.Dop1Array".freeze
        # The wire codes of the app's Dop2AttributeFactory, by attribute class (in its Attributes or Arrays namespace).
        WIRES = %w[Bool U8 S8 E8 U16 S16 E16 U32 S32 E32 U64 S64 E64 Float Double Struct ABool AU8 AS8 AE8 AU16 AS16
                   AE16 AU32 AS32 AE32 AU64 AS64 AE64 AFloat ADouble String AStruct]
                .each.with_index(1).to_h { |name, code| ["Dop2_#{name}", code] }.freeze
        CONSTANT = /\bldc\.i4(?:\.s)?\s+(0x\h+|-?\d+)\b|\bldc\.i4\.(m1|\d)\b/

        # @param line [String]
        # @return [Integer, nil] the integer it pushes
        def self.constant(line)
          match = line.match(CONSTANT) or return
          value = match[1] || match[2]
          return -1 if value == 'm1'

          value.start_with?('0x') ? value.to_i(16) : value.to_i
        end

        # @param lines [Array<String>]
        # @return [Array<Integer>]
        def self.constants(lines) = lines.filter_map { constant(it) }

        # @param classes [Array<IlModel::Klass>]
        def initialize(classes)
          @classes = classes
          @by_name = classes.group_by(&:name).transform_values(&:first)
        end

        # @return [Hash{String=>Hash}] by class name: assembly and fields by attribute index
        def dop2
          @classes.select { IlModel.bare(it.extends) == DOP2 }.to_h do |klass|
            fields = klass.procedures.select { it.name.to_s.start_with?('get_') }.filter_map { dop2_field(it) }
            [klass.name, { 'assembly' => klass.assembly, 'fields' => fields.sort_by { it['index'] } }]
          end
        end

        # @return [Hash{String=>Hash}] by class name: assembly, object id, endianness, sections, arrays and fields
        def dop1
          own = @classes.select { dop1?(it) }.to_h { [it.name, Dop1Layout.new(it, @by_name).to_h] }
          own.to_h { |name, layout| [name, with_base(own, name, layout)] }
        end

        # @return [Hash{String=>Hash}] by enum name: assembly and values
        def enums
          @classes.select { IlModel.bare(it.extends) == 'System.Enum' }.to_h do |klass|
            [klass.name, { 'assembly' => klass.assembly, 'values' => klass.fields.filter_map { literal(it) } }]
          end
        end

        private

        HELPERS = { 'GetGeneratedObject' => 'scalar', 'GetGeneratedObjects' => 'struct_array', 'GetEnum' => 'enum',
                    'GetEnums' => 'enum_array' }.freeze
        private_constant :HELPERS

        # @return [Array(String, Integer), nil] an enum value: name and number
        def literal(field)
          match = field.match(/literal .* (\S+) = (?:int|uint)\d+\((-?)(0x\h+|\d+)\)/) or return
          [match[1], Integer(match[3], 0) * (match[2].empty? ? 1 : -1)]
        end

        def dop2_field(method)
          body = method.body
          call = body.index { it.match?(/Dop2Object::(?:GetGeneratedObjects?|GetEnums?)</) } or return
          line = body[call]
          helper = line[/Dop2Object::(\w+)</, 1]
          { 'index' => Layouts.constants(body[0...call]).last, 'name' => method.name.delete_prefix('get_'),
            **kind(helper, IlModel.bare(line[/#{helper}<(.+?)>\(/, 1].to_s.split(',').first)) }
        end

        def kind(helper, type)
          wire = WIRES[type.split('.').last] if type.start_with?("#{PROTOCOLS}.Dop2.")
          unless helper == 'GetGeneratedObject'
            return { 'kind' => HELPERS.fetch(helper), 'wire' => nil, 'type' => type }
          end
          return { 'kind' => 'struct', 'wire' => 16, 'type' => type } unless wire

          { 'kind' => wire_kind(wire), 'wire' => wire, 'type' => nil }
        end

        def wire_kind(wire)
          case wire
          when 32 then 'string'
          when 17..31 then 'array'
          else 'scalar'
          end
        end

        # The hood's ExtendedDopDeviceState is its DeviceState read MSB, and ExtendedDop2DeviceState the same read LSB
        # with two more sections.
        def with_base(layouts, name, layout)
          base_name = IlModel.bare(@by_name[name].extends)
          base = layouts[base_name] or return layout
          base = with_base(layouts, base_name, base)
          layout.merge(%w[sections arrays fields].to_h { [it, base[it] + layout[it]] },
                       'id' => layout['id'] || base['id'], 'endian' => layout['endian'] || base['endian'])
        end

        def dop1?(klass)
          seen = []
          base = IlModel.bare(klass.extends)
          until base.empty? || seen.include?(base)
            return true if [DOP1, DOP1_ARRAY].include?(base) || base == "#{PROTOCOLS}.Dop1.Dop1Bitfield"

            seen << base
            base = IlModel.bare(@by_name[base]&.extends)
          end
          false
        end
      end
    end
  end
end
