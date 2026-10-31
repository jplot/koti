# frozen_string_literal: true

module Schema
  module Extract
    module Objects
      # Where the app reads or writes each DOP2 class: [unit, attribute] when it sends no index, else [unit, attribute,
      # idx1, idx2], nil for an index it computes. The classes carry no address, and these rules miss what the app
      # computes or passes on, so they only check the hand-made table.
      class Addresses
        # Calls whose literal arguments are the unit, the attribute and, when given, idx1 and idx2.
        CALLS = /::(?:GetDop2FieldAsync|GetDop2FieldCachedAsync|ObserveDop2Field|WriteDop2FieldAsync)</
        private_constant :CALLS

        NAME = %r{Miele\.[\w.]+(?:/\w+)*}
        private_constant :NAME

        # @param classes [Array<IlModel::Klass>]
        # @param dop2 [Hash{String=>Object}] the DOP2 classes, by name
        def initialize(classes, dop2)
          @classes = classes
          @by_name = classes.group_by(&:name).transform_values(&:first)
          @dop2 = dop2
          @found = Hash.new { |hash, key| hash[key] = [] }
        end

        # @return [Hash{String=>Array<Array<Integer, nil>>}] by class name
        def find
          @classes.each do |klass|
            klass.procedures.each { literal_calls(it.body) }
            request_parameters(klass)
            overrides(klass)
          end
          @found.transform_values(&:uniq)
        end

        private

        def dop2_in(text) = text.to_s.gsub(/\[[^\]]*\]/, '').scan(NAME).select { @dop2.key?(it) }.uniq

        def add(names, unit, attribute, *indexes)
          names.each { @found[it] << [unit, attribute, *indexes] } if unit && attribute
        end

        def literal_calls(body)
          window = []
          body.each do |line|
            next window << line unless line.match?(/\b(?:call|callvirt|newobj)\b/)

            values = Layouts.constants(window)
            add(dop2_in(line), *values) if line.match?(CALLS) && [2, 4].include?(values.size)
            window = []
          end
        end

        # A source built with +new Dop2RequestParameters(objectId, unit)+ for the DOP2 class its base takes.
        def request_parameters(klass)
          names = dop2_in(klass.extends)
          return if names.empty?

          klass.procedures.select { it.name == '.ctor' }.each do |ctor|
            values = parameters(ctor.body) or next
            add(names, values.last, values.first) if values.size == 2
          end
        end

        # @return [Array<Integer>, nil] the constants pushed before +new Dop2RequestParameters+
        def parameters(body)
          index = body.index { it.include?('Dop2RequestParameters::.ctor') } or return
          Layouts.constants(body[0...index])
        end

        # A message or action overriding get_Unit and get_ObjectId (and get_Idx1, get_Idx2) for its base's class.
        def overrides(klass)
          names = dop2_in(klass.extends)
          return if names.empty?

          unit, attribute, idx1, idx2 = %w[get_Unit get_ObjectId get_Idx1 get_Idx2].map { returned(klass, it) }
          add(names, unit, attribute, idx1, idx2)
        end

        # The literal +name+ returns, from the class or the nearest base that overrides it.
        def returned(klass, name)
          until klass.nil?
            body = klass.procedures.find { it.name == name }&.body
            return (Layouts.constant(body.first.to_s) if body.size == 2) if body

            klass = @by_name[IlModel.bare(klass.extends)]
          end
        end
      end
    end
  end
end
