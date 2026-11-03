# frozen_string_literal: true

require 'json'

# Writes the typed values of lib/hue/sdk/schema/ and their signatures from schema/hue.json and schema/behaviors.json.
# Run `rake schema`.
class SchemaGenerator
  FILES = { 'behavior' => 'behaviors', 'response' => 'responses', 'update' => 'updates', 'add' => 'creates',
            'change' => 'changes' }.freeze
  # The table of value classes a file ends with, by resource type.
  TABLES = { 'response' => ['RESPONSES', 'response', 'Response value class of each resource type.'],
             'change' => ['CHANGES', 'change', 'Value class of the changes of an event, by resource type.'] }.freeze
  WIDTH = 120

  # @param root [String] the folder of the gem
  def self.load(root) = new(*%w[hue behaviors].map { JSON.parse(File.read(File.join(root, 'schema', "#{it}.json"))) })

  def initialize(schema, behaviors)
    @classes = schema.fetch('classes').merge(behaviors.fetch('classes'))
    behaviors.fetch('overrides').each { |name, fields| override(@classes.fetch(name).fetch('fields'), fields) }
    @resources = schema.fetch('resources').merge(behaviors.fetch('resources')) { |_, slots, more| slots.merge(more) }
    @scripts = behaviors.fetch('scripts')
    Changes.add(@classes, @resources)
  end

  def files
    ruby = RubyWriter.new(@classes, @resources, @scripts)
    rbs = RbsWriter.new(@classes, @resources, @scripts)
    FILES.each_with_object({}) do |(kind, name), files|
      files["lib/hue/sdk/schema/#{name}.rb"] = ruby.file(kind, ordered(kind))
      files["sig/hue/sdk/schema/#{name}.rbs"] = rbs.file(kind, ordered(kind))
    end.merge('sig/hue/sdk/schema/models.rbs' => rbs.models)
  end

  def write(root) = files.each { |path, content| File.write(File.join(root, path), content) }

  # A configuration of an automation script is the only class that keeps the keys it does not know.
  def self.script(fields) = fields.key?('unknown') ? ['        include ScriptConfiguration'] : []

  def self.held(type)
    return unless type.is_a?(Hash)

    type['class'] || held(type['list'] || type['map'])
  end

  private

  def override(fields, changes) = changes.each { |key, change| fields[key] = fields.fetch(key).merge(change) }

  # Classes of one kind, each after the classes it holds, so that its declaration can name them. A class of another
  # kind stays in the file of its own.
  def ordered(kind)
    names = @classes.select { |_, c| c['kind'] == kind }.keys.sort
    names.each_with_object([]) { |name, done| visit(name, done) }.select { @classes[it]['kind'] == kind }
  end

  def visit(name, done)
    return if done.include?(name)

    @classes[name]['fields'].each_value { |field| (inner = self.class.held(field['type'])) && visit(inner, done) }
    done << name
  end

  # The changes of a resource as an event reports them: the classes of its response, with every field optional, as the
  # +*Updated+ classes of the app are (all 179 decode the same keys as their +*Added+ class).
  module Changes
    module_function

    def add(classes, resources)
      names = reached(classes, resources.each_value.map { it.fetch('response') })
      classes.merge!(names.to_h { [change_of(it), twin(classes.fetch(it))] })
      resources.each_value { it['change'] = change_of(it.fetch('response')) }
    end

    def reached(classes, names) = names.each { |name| names.concat(held(classes.fetch(name)) - names) }

    def held(cls) = cls['fields'].values.filter_map { SchemaGenerator.held(it['type']) }.uniq

    def change_of(origin) = "#{origin}Change"

    def twin(cls)
      fields = cls['fields'].transform_values { it.merge('type' => type(it['type']), 'required' => false) }
      { 'origin' => cls['origin'].sub(/Added\z/, 'Updated'), 'kind' => 'change', 'fields' => fields }
    end

    def type(type)
      return type if type.is_a?(String)
      return { 'class' => change_of(type['class']) } if type['class']

      type.transform_values { type(it) }
    end
  end

  # Writes the tables of the automation scripts.
  module ScriptTables
    module_function

    def ruby(scripts)
      names = scripts.map { |id, script| "  #{script['name']}: '#{id}'" }.sort.join(",\n")
      classes = scripts.map { |id, script| "  '#{id}' => #{script['configuration']}" }.sort.join(",\n")
      <<~RUBY.gsub(/^(?=.)/, '      ')
        # Id of each automation script, by a stable name.
        BEHAVIOR_SCRIPTS = {
        #{names}
        }.freeze

        # Configuration value class of each automation script, by its id.
        BEHAVIOR_CONFIGURATIONS = {
        #{classes}
        }.freeze
      RUBY
    end

    def rbs(scripts)
      classes = scripts.each_value.map { it['configuration'] }.uniq.sort
      <<~RBS.gsub(/^(?=.)/, '      ')
        type behavior_configuration = #{classes.join(' | ')} | Hash[String, untyped]

        BEHAVIOR_SCRIPTS: Hash[Symbol, String]

        BEHAVIOR_CONFIGURATIONS: Hash[String, Value::ClassMethods]
      RBS
    end
  end

  # Writes the Ruby value classes.
  class RubyWriter
    YARD = { 'String' => 'String', 'Integer' => 'Integer', 'Numeric' => 'Numeric', 'Boolean' => 'Boolean',
             'Hash' => 'Hash{String=>Object}', 'Object' => 'Object',
             'BehaviorConfiguration' => 'Value, Hash{String=>Object}' }.freeze
    SUMMARY = {
      'change' => ['Part of the changes of a resource', 'The changes of a +%s+ resource, as an event reports them'],
      'behavior' => ['Part of an automation as the Hue app describes it', nil],
      'response' => ['Part of a resource as the bridge reports it', 'The +%s+ resource as the bridge reports it'],
      'update' => ['Part of the changes sent to update a resource', 'The changes sent to update a +%s+ resource'],
      'add' => ['Part of a resource sent to create it', 'A +%s+ resource sent to create it']
    }.freeze
    # Members the bridge names like a method of Data; they shadow it, which the value classes never call.
    SHADOWING = 'Lint/DataDefineOverride -- the bridge names this key'

    def initialize(classes, resources, scripts)
      @classes = classes
      @resources = resources
      @scripts = scripts
    end

    def file(kind, names)
      body = names.map { define(it) }.join("\n")
      body += "\n#{table(*TABLES[kind])}" if TABLES[kind]
      body += "\n#{ScriptTables.ruby(@scripts)}" if kind == 'behavior'
      "# frozen_string_literal: true\n\n# Generated by schema/generate.rb from its data in schema/: do not edit.\n\n" \
        "module Hue\n  module Sdk\n    module Schema\n#{body}    end\n  end\nend\n"
    end

    private

    def define(name)
      fields = @classes[name]['fields']
      shadowing = fields.keys.intersect?(Data.instance_methods.map(&:to_s))
      lines = [*docs(name), head(name, fields), '        include Value', *SchemaGenerator.script(fields),
               *macros(fields), '      end']
      lines = shadow(lines) if shadowing
      "#{lines.join("\n")}\n"
    end

    def shadow(lines)
      ["      # rubocop:disable #{SHADOWING}", '', *lines, "      # rubocop:enable #{SHADOWING.split.first}"]
    end

    def head(name, fields)
      return "      #{name} = Data.define do" if fields.empty?

      wrap("      #{name} = Data.define(", fields.keys.map { ":#{it}" }, ') do')
    end

    def macros(fields)
      optional = fields.reject { |_, f| f['required'] }.keys.map { ":#{it}" }
      nested = fields.filter_map { |key, field| nested(key, field['type']) }
      lines = [optional.any? && wrap('        optional ', optional, ''),
               nested.any? && wrap('        nested ', nested, '')].grep(String)
      lines.any? ? ['', *lines] : []
    end

    def nested(key, type) = ("#{key}: #{nested_type(type)}" if SchemaGenerator.held(type))

    def nested_type(type)
      return type['class'] if type['class']

      type['map'] ? "{ String => #{nested_type(type['map'])} }" : "[#{nested_type(type['list'])}]"
    end

    def docs(name)
      cls = @classes[name]
      attributes = cls['fields'].flat_map { |key, field| attribute(key, field) }
      lines = paragraph(description(name, cls), '')
      lines.push('', *attributes) if attributes.any?
      lines.map { "      # #{it}".rstrip }
    end

    def description(name, cls)
      return "#{summary(name, cls['kind'])} (Hue app class +#{cls['origin']}+)." unless cls['fields'].key?('unknown')

      "The configuration of the +#{cls['origin']}+ automation script, from the steps of its definition in the Hue app."
    end

    def attribute(key, field) = ["@!attribute [r] #{key}", *paragraph("@return [#{yard(field)}]#{values(field)}", '  ')]

    def summary(name, kind)
      type, = @resources.find { |_, slots| slots.value?(name) }
      part, resource = SUMMARY.fetch(kind)
      type ? format(resource, type) : part
    end

    def yard(field)
      type = yard_type(field['type'])
      field['required'] ? type : "#{type}, nil"
    end

    def yard_type(type)
      return YARD.fetch(type) if type.is_a?(String)
      return "Hash{String=>#{yard_type(type['map'])}}" if type['map']

      type['class'] || "Array<#{yard_type(type['list'])}>"
    end

    def values(field)
      return '' unless field['values']

      names = field['values'].map { "+#{it}+" }.join(', ')
      " one of #{names}#{', or a hash to recall a scene' if field['type'] == 'Object'}"
    end

    def paragraph(text, indent)
      text.split.each_with_object([+indent]) do |word, lines|
        lines << "#{indent}  " if lines.last.length + word.length + 9 > WIDTH
        lines.last << (lines.last.strip.empty? ? word : " #{word}")
      end
    end

    def wrap(head, items, tail)
      pieces = [*items[...-1].map { "#{it}," }, "#{items.last}#{tail}"]
      pieces.each_with_object([head.dup]) { |piece, lines| append(lines, piece, head.length) }.join("\n")
    end

    def append(lines, piece, indent)
      lines << (' ' * indent) if lines.last.length + piece.length + 1 > WIDTH
      lines.last << (lines.last.end_with?('(', ' ') ? piece : " #{piece}")
    end

    def table(constant, slot, comment)
      entries = @resources.map { |type, slots| "        '#{type}' => #{slots.fetch(slot)}" }.join(",\n")
      "      # #{comment}\n      #{constant} = {\n#{entries}\n      }.freeze\n"
    end
  end

  # Writes the RBS signatures of the value classes, and the typed methods of the models.
  class RbsWriter
    TYPES = { 'String' => 'String', 'Integer' => 'Integer', 'Numeric' => 'Numeric', 'Boolean' => 'bool',
              'Hash' => 'Hash[String, untyped]', 'Object' => 'untyped',
              'BehaviorConfiguration' => 'behavior_configuration' }.freeze

    def initialize(classes, resources, scripts)
      @classes = classes
      @resources = resources
      @scripts = scripts
    end

    def file(kind, names)
      body = names.map { declare(it) }.join("\n")
      body += "\n      #{TABLES[kind].first}: Hash[String, Value::ClassMethods]\n" if TABLES[kind]
      body += "\n#{ScriptTables.rbs(@scripts)}" if kind == 'behavior'
      "module Hue\n  module Sdk\n    module Schema\n#{body}    end\n  end\nend\n"
    end

    def models
      body = @resources.map { |type, slots| model(type, slots) }.join("\n")
      "module Hue\n  module Sdk\n    module Models\n#{body}    end\n  end\nend\n"
    end

    private

    def declare(name)
      fields = @classes[name]['fields']
      readers = fields.map { |key, field| "        attr_reader #{key}: #{type(field)}" }
      params = fields.map { |key, field| "#{'?' unless field['required']}#{key}: #{type(field)}" }
      ["      class #{name} < Data", '        include Value', *SchemaGenerator.script(fields),
       '        extend Value::ClassMethods', '', *readers,
       ('' if readers.any?), "        def self.new: (#{params.join(', ')}) -> #{name}",
       "        def self.from: (Hash[String, untyped] data) -> #{name}", "      end\n"].compact.join("\n")
    end

    def type(field) = "#{plain(field['type'])}#{'?' unless field['required']}"

    def plain(type)
      return TYPES.fetch(type) if type.is_a?(String)
      return "Hash[String, #{plain(type['map'])}]" if type['map']

      type['class'] || "Array[#{plain(type['list'])}]"
    end

    def model(type, slots)
      ["      class #{type.split('_').map(&:capitalize).join} < Base", *create(slots['create']),
       '        class Instance < Base::Instance', "          def attributes: () -> Schema::#{slots.fetch('response')}",
       *update(slots['update']), '        end', "      end\n"].join("\n")
    end

    def create(request)
      return [] unless request

      ["        def create: (Schema::#{request} request, **untyped attributes) -> Instance",
       '                  | (**untyped attributes) -> Instance', '']
    end

    def update(request)
      return [] unless request

      ["          def update: (Schema::#{request} request, **untyped attributes) -> self",
       '                    | (**untyped attributes) -> self']
    end
  end
end

SchemaGenerator.load(File.dirname(__dir__)).write(File.dirname(__dir__)) if $PROGRAM_NAME == __FILE__
