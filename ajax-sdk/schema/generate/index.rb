# frozen_string_literal: true

require_relative 'model'

module Schema
  module Generate
    # Writes messages.rb and messages.rbs: the modules of the packages, an autoload for each type outside any
    # message, and +TYPES+, the value class of each request and response of methods.tsv.
    module Index
      Node = Struct.new(:package, :children, :types)
      ROOT = 'Ajax::Sdk::Cloud::Messages'
      OUTER = %w[Ajax Sdk Cloud].freeze

      module_function

      # @return [String] messages.rb
      def ruby(model)
        types = model.roots.map { "  '#{it}' => '#{model.type(it).constant.delete_prefix("#{ROOT}::")}'," }
        messages = ['# The typed values of the cloud messages, generated from lib/ajax/sdk/cloud/schemas/: a Data',
                    '# class per message and a module per enum, each loaded on its first use.', 'module Messages',
                    *Ruby.indent(ruby_node(tree(model))), '',
                    '  # The value class of each request and response of the method table, by protobuf name.',
                    '  TYPES = {', *types.map { "  #{it}" }, '  }.freeze', 'end']
        [Ruby::HEADER, *wrap(messages), ''].join("\n")
      end

      # @return [String] messages.rbs
      def rbs(model)
        messages = ['module Messages', '  TYPES: ::Hash[::String, ::String]', '', *Ruby.indent(rbs_node(tree(model))),
                    'end']
        [Rbs::HEADER, '', *wrap(messages), ''].join("\n")
      end

      def wrap(lines) = OUTER.reverse.reduce(lines) { |inner, name| ["module #{name}", *Ruby.indent(inner), 'end'] }

      def tree(model)
        Node.new(nil, {}, []).tap do |root|
          model.files.each do |proto|
            model.top_level(proto).each { add(root, model, it, proto.delete_suffix('.proto')) }
          end
        end
      end

      def add(root, model, type, stem)
        *modules, short = type.constant.delete_prefix("#{ROOT}::").split('::')
        packages = packages(model.package(type.full_name))
        node = modules.each_with_index.reduce(root) do |parent, (name, depth)|
          parent.children[name] ||= Node.new(packages.fetch(depth), {}, [])
        end
        node.types << [short, stem]
      end

      # @return [Array<String>] the package of each module of +package+: +systems.ajax+ gets none
      def packages(package)
        segments = package.split('.')
        skipped = segments.first(2) == %w[systems ajax] ? 2 : 0
        (skipped...segments.size).map { segments.first(it + 1).join('.') }
      end

      def ruby_node(node)
        autoloads = node.types.map { |short, stem| "autoload :#{short}, \"\#{__dir__}/messages/#{stem}.rb\"" }
        modules = node.children.map do |name, child|
          ['', "# Package +#{child.package}+.", "module #{name}", *Ruby.indent(ruby_node(child)), 'end']
        end
        [*autoloads, *modules.flatten].drop_while(&:empty?)
      end

      def rbs_node(node)
        node.children.flat_map { |name, child| ['', "module #{name}", *Ruby.indent(rbs_node(child)), 'end'] }
            .drop_while(&:empty?)
      end
    end
  end
end
