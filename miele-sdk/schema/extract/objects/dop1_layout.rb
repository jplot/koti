# frozen_string_literal: true

module Schema
  module Extract
    module Objects
      # One Dop1 class: a view on an object's bytes, with its fields and the sections and arrays it holds.
      class Dop1Layout
        SIZES = { 'U8' => 1, 'S8' => 1, 'U16' => 2, 'S16' => 2, 'U32' => 4, 'S32' => 4 }.freeze
        private_constant :SIZES

        # @param klass [IlModel::Klass]
        # @param by_name [Hash{String=>IlModel::Klass}]
        def initialize(klass, by_name)
          @klass = klass
          @by_name = by_name
        end

        # @return [Hash]
        def to_h
          arrays, sections = parts.partition { it.key?('count') }
          { 'assembly' => @klass.assembly, 'id' => id, 'endian' => endian, 'sections' => sections, 'arrays' => arrays,
            'fields' => fields, 'write' => write?, 'write_bytes' => write_bytes }
        end

        private

        def method(name) = @klass.procedures.find { it.name == name }

        def id = method('get_Dop1ObjectId')&.body&.filter_map { it[/ldstr\s+"([^"]*)"/, 1] }&.first

        # The app passes 1 (most significant byte first) or 0 to its base's constructor: from (data, offset, length),
        # or from the parameterless constructor of a write section it builds alone (the hood's 8E01 one: 2 bytes, 1).
        def endian
          call = "#{IlModel.bare(@klass.extends)}::.ctor(uint8[],"
          @klass.procedures.select { it.name == '.ctor' }.filter_map do |ctor|
            index = ctor.body.index { it.include?(call) } or next
            { 1 => 'msb', 0 => 'lsb' }[Layouts.constant(ctor.body[index - 1].to_s)]
          end.first
        end

        # Sections and arrays the constructors create, each with the constants pushed since the previous call.
        def parts
          @parts ||= @klass.procedures.select { it.name == '.ctor' }.flat_map { created(it.body) }.uniq
        end

        def created(body)
          start = 0
          body.each_with_index.filter_map do |line, index|
            type = line[/newobj\s+instance void (.+?)::\.ctor\(uint8\[\]/, 1]
            unless type
              start = index + 1 if line.match?(/\bcall\b|\bstfld\b/) && !line.match?(/get_|ldfld/)
              next
            end
            part(IlModel.bare(type), body[start...index]).tap { start = index + 1 }
          end
        end

        def part(type, window)
          values = Layouts.constants(window)
          computed = window.any? { it.match?(/\b(?:add|sub|mul)\b/) }
          if array?(type)
            return { 'type' => type, 'offset' => values[-3], 'count' => values[-2], 'width' => values[-1] }
          end

          { 'type' => type, 'offset' => values[-2], 'length' => values[-1], 'computed' => computed }
        end

        def array?(type) = IlModel.bare(@by_name[type]&.extends) == Layouts::DOP1_ARRAY

        def fields = @klass.procedures.filter_map { field(it) }

        def field(method)
          if (call = method.body.index { it.match?(/Dop1Object::Get[US]\d+\(/) })
            word = method.body[call][/Dop1Object::Get([US]\d+)\(/, 1]
            return field_of(method, 'kind' => word.downcase, 'offset' => Layouts.constants(method.body[0...call]).last,
                                    'size' => SIZES.fetch(word))
          end
          bits(method)
        end

        def bits(method)
          call = method.body.index { it.include?('Dop1Bitfield::GetBitValue') } or return
          offset, length = Layouts.constants(method.body[0...call]).last(2)
          field_of(method, 'kind' => 'bits', 'offset' => offset, 'length' => length)
        end

        def field_of(method, layout)
          { 'name' => method.name.delete_prefix('get_'), **layout,
            'type' => IlModel.bare(method.header[/instance\s+(.+?)\s+'?get_/, 1]) }
        end

        def write? = @klass.implements.any? { it.end_with?('IWriteableDop1Object') }

        def write_bytes
          body = method('GenerateWriteBytes')&.body or return
          body.each_index.filter_map { piece(body, it) }
        end

        # A slice of the bytes, or the bytes of a section: the dishwasher's 8906 and laundry's 8201 append their
        # extras bit fields.
        def piece(body, index)
          return Layouts.constants(body[[0, index - 4].max...index]).last(2) if body[index].include?('GetSubArray')

          type = body[index][/call\s+instance\s+class\s+(\S+)\s+\S+::get_\w+\(\)/, 1] or return
          section = parts.find { it['type'] == IlModel.bare(type) }
          [section.fetch('offset'), section.fetch('length')]
        end
      end
    end
  end
end
