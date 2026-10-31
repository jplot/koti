# frozen_string_literal: true

module Schema
  module Extract
    # The DOP2 and Dop1 objects of the Miele app, read from the IL ikdasm prints for its assemblies.
    module Objects
      # The classes of one assembly's IL: name (a nested one is Outer/Inner), base as written (generic arguments
      # included), interfaces, fields, and methods with their IL lines.
      class IlModel
        Klass = Struct.new(:name, :assembly, :extends, :implements, :fields, :procedures)
        Meth = Struct.new(:name, :header, :body)

        MODIFIERS = /\A(?:[a-z]+\s+)+/
        private_constant :MODIFIERS

        # @param path [String] an +.il+ file
        # @return [Array<Klass>]
        def self.parse(path)
          model = new(File.basename(path, '.il'))
          File.foreach(path, encoding: 'UTF-8') { model.step(it.chomp.scrub) }
          model.classes
        end

        # @return [Array<Klass>]
        attr_reader :classes

        # @param assembly [String]
        def initialize(assembly)
          @assembly = assembly
          @classes = []
          @stack = []
        end

        # @param line [String]
        # @return [void]
        def step(line)
          if @class_header then class_header(line)
          elsif @method_header then method_header(line)
          else statement(line)
          end
        end

        # A generic type name without its arguments, its assembly prefixes, nor the quotes ikdasm puts around a name
        # outside ASCII (+'BestätigungNotwendigEnum'+).
        #
        # @param text [String]
        # @return [String]
        def self.bare(text)
          depth = 0
          text = text.to_s.delete("'").sub(/\A(?:class|valuetype)\s+/, '').gsub(/\[[^\]]*\]/, '')
          text.each_char.with_object(+'') do |char, out|
            depth += { '<' => 1, '>' => -1 }.fetch(char, 0)
            out << char if depth.zero? && char != '>'
          end.strip
        end

        private

        STATEMENTS = {
          /\A\s*\.class\s/ => ->(line) { @class_header = line.strip },
          /\A\s*\.method\s/ => ->(line) { open_method(line.strip) },
          %r{\A\s*\} // end of class} => ->(_) { @stack.pop },
          %r{\A\s*\} // end of method} => ->(_) { @method = nil },
          /\A\s*\.field\s/ => ->(line) { @stack.last&.fields&.push(line.strip) },
          /\A\s*IL_\h+:/ => ->(line) { @method&.body&.push(line.strip) }
        }.freeze
        private_constant :STATEMENTS

        def statement(line)
          handler = STATEMENTS.find { |pattern, _| line.match?(pattern) }&.last
          instance_exec(line, &handler) if handler
        end

        def class_header(line)
          return @class_header << ' ' << line.strip unless line.strip == '{'

          open_class(@class_header)
          @class_header = nil
        end

        def open_class(header)
          text = header.sub(/\A\.class\s+/, '').sub(MODIFIERS, '')
          name = [@stack.last&.name, IlModel.bare(text.split(/\s+(?:extends|implements)\s+/).first)].compact.join('/')
          extends = text[/\sextends\s+(.+?)(?:\s+implements\s|\z)/, 1]
          klass = Klass.new(name, @assembly, extends, interfaces(text), [], [])
          @classes << klass
          @stack.push(klass)
        end

        def interfaces(text) = text[/\simplements\s+(.+)\z/, 1].to_s.split(/,\s*(?![^<]*>)/).map { IlModel.bare(it) }

        def open_method(header)
          @method_header = header
          method_header(nil)
        end

        def method_header(line)
          @method_header << ' ' << line.strip if line
          return unless @method_header.match?(/\b(?:cil|runtime)\s+managed\b/)

          @method = Meth.new(method_name(@method_header), @method_header, [])
          @stack.last&.procedures&.push(@method)
          @method_header = nil
        end

        def method_name(header)
          text = header.sub(/\s*(?:cil|runtime)\s+managed.*\z/, '').rstrip
          before = text[0...opening(text, ')', '(')].to_s.rstrip
          before = before[0...opening(before, '>', '<')].to_s if before.end_with?('>')
          before[/(\S+)\z/, 1]&.delete("'")
        end

        # @return [Integer] where the bracket closing +text+ opens
        def opening(text, close, open)
          depth = 0
          (text.size - 1).downto(0) do |index|
            depth += { close => 1, open => -1 }.fetch(text[index], 0)
            return index if depth.zero?
          end
          text.size
        end
      end
    end
  end
end
