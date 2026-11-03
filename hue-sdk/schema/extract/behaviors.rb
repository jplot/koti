# frozen_string_literal: true

require 'yaml'
require_relative 'classes'
require_relative 'responses'

module Schema
  module Extract
    # One fromJson written by json_serializable, walked like the app's RAML classes. It also tells a key read twice,
    # for a null check, from one read once, and an enum, decoded through the map of its values.
    class BehaviorFromJson < FromJson
      NESTED = /\A\._\$(\w+)FromJson\z/
      ENUM = /\AMap<(\w+), String>\(\d+\) \{\z/

      def initialize(snapshot, name)
        super
        @reads = Hash.new(0)
      end

      # @return [Hash{String=>Hash}] by key, what {FromJson} tells of it, and how many times it was read
      def decoded(instructions) = fields(instructions).to_h { |key, field| [key, field.merge('reads' => @reads[key])] }

      private

      def load(register, offset)
        super
        enum = @snapshot.object(offset).to_s[ENUM, 1]
        describe('enum', enum) if enum
      end

      def call(target)
        case @snapshot.owner(target.hex).to_s
        when NESTED then describe('class', Regexp.last_match(1))
        when '.$enumDecode' then describe('always', true)
        else consume
        end
        @key = nil
      end

      def consume
        @reads[@key] += 1 if @key
        super
      end
    end

    # The classes of the app's automations that some roots reach, as hue.json describes a class. They come from
    # json_serializable, not from the API description, so the code alone tells which keys are required.
    class BehaviorClasses
      # @param snapshot [Snapshot]
      # @param taken [Array<String>] the classes of hue.json, whose names these classes cannot use
      def initialize(snapshot, taken:)
        @snapshot = snapshot
        @taken = taken
      end

      # @param roots [Array<String>] classes of the app
      # @return [Hash{String=>Hash}] the classes by name
      # @raise [ArgumentError] for a name hue.json takes, or a class without fromJson
      def read(roots)
        queue = roots.dup
        queue.each_with_object({}) do |origin, classes|
          next if classes.key?(name(origin))

          decoded = decoded(origin)
          fields = decoded.transform_values { field(it) }
          classes[name(origin)] = { 'origin' => origin, 'kind' => 'behavior', 'fields' => fields }
          queue.concat(decoded.values.filter_map { held(it) })
        end
      end

      private

      def decoded(origin)
        address, size = @snapshot.function("._$#{origin}FromJson")
        raise ArgumentError, "no fromJson for #{origin}" unless address

        BehaviorFromJson.new(@snapshot, origin).decoded(@snapshot.instructions(address, size))
      end

      def name(origin)
        origin.delete_prefix('Bridge').tap do |name|
          raise ArgumentError, "#{origin} would take the name #{name}, which hue.json has" if @taken.include?(name)
        end
      end

      def field(decoded)
        values = @snapshot.enum_values(decoded['enum'] || decoded['items'])
        field = { 'type' => type(decoded, values), 'required' => required?(decoded) }
        values ? field.merge('values' => values) : field
      end

      def type(decoded, values)
        return 'String' if decoded['enum']
        return { 'class' => name(decoded['class']) } if decoded['class']
        return { 'list' => values ? 'String' : item(decoded['items']) } if decoded['items']

        dart = decoded['type'].to_s.delete_suffix('?')
        Types.primitive(dart) || (dart.start_with?('Map<') ? 'Hash' : 'Object')
      end

      def item(dart) = Types.primitive(dart) || { 'class' => name(dart) }

      def required?(decoded)
        return decoded.key?('always') if decoded['enum']

        decoded['reads'] == 1 && !decoded['type'].to_s.end_with?('?')
      end

      def held(decoded)
        items = decoded['items']
        decoded['class'] || (items unless Types.primitive(items) || @snapshot.enum_values(items))
      end
    end

    # The configuration of each automation script. The app has no class for one: the steps of its definition, in the
    # assets of the APK, name its keys, and the type of a step gives the value it writes (BehaviorEncoder).
    class BehaviorScripts
      STEPS = {
        'lights_selection' => { 'list' => { 'class' => 'BehaviorGroupAndLights' } },
        'scene_selection' => { 'list' => { 'class' => 'BehaviorGroupScene' } },
        'time_and_recurrence_selection' => { 'class' => 'BehaviorWhen' },
        'when_extended_selection' => { 'class' => 'BehaviorWhenExtended' },
        'when_selection' => { 'class' => 'BehaviorWhenConstrained' },
        'fade_selection' => { 'class' => 'BehaviorFadeDuration' },
        'duration_selection' => { 'class' => 'TimeSpan' },
        'lights_off_after_selection' => { 'class' => 'TimeSpan' },
        'streaming_end_scene_selection' => { 'class' => 'BehaviorStreamingEndScene' },
        'end_state_selection' => 'String',
        'streaming_end_state_selection' => 'String',
        'option_selection_step' => 'String',
        'brightness_selection' => 'Numeric'
      }.freeze
      ENUMS = { 'end_state_selection' => 'BridgeBehaviorEndStateType',
                'streaming_end_state_selection' => 'BridgeBehaviorStreamingEndStateType' }.freeze
      # Switching the first off omits its key; only the end state +scene+ uses the second.
      OPTIONAL = %w[lights_off_after_selection streaming_end_scene_selection].freeze
      # The keys the app keeps as they are (BridgeStepResultValueUnknown), and sends back.
      UNKNOWN = { 'type' => 'Hash', 'required' => false }.freeze
      # Unknown to the app; the bridge gives it the same +$ref+ as go to sleep.
      NATIVE = { 'a5624529-bd7e-4bc8-9d2f-9200476f106e' => { 'name' => 'native_go_to_sleep',
                                                             'configuration' => 'GoToSleepConfiguration' } }.freeze

      # @param directory [String] the +behaviors+ folder of the assets of the APK
      # @param snapshot [Snapshot]
      def initialize(directory, snapshot)
        @directory = directory
        @snapshot = snapshot
      end

      # @return [Hash] +scripts+ by uuid, and +classes+ by name
      # @raise [ArgumentError] for a step type this reader does not know
      def read
        scripts = definitions.to_h { |name, definition| [definition.fetch('script_id'), script(name)] }
        classes = definitions.to_h { |name, definition| [class_name(name), configuration(name, definition)] }
        { 'scripts' => scripts.merge(NATIVE), 'classes' => classes }
      end

      private

      def definitions
        @definitions ||= Dir[File.join(@directory, '*', 'behavior.yaml')].to_h do |path|
          [File.basename(File.dirname(path)), YAML.load_file(path)]
        end
      end

      def script(name) = { 'name' => name, 'configuration' => class_name(name) }

      def class_name(name) = "#{name.split('_').map(&:capitalize).join}Configuration"

      def configuration(name, definition)
        edited = steps(definition['editing'])
        fields = steps(definition['creation']).to_h { |key, step| [key, field(step, edited[key])] }
        { 'origin' => name, 'kind' => 'behavior', 'fields' => fields.merge('unknown' => UNKNOWN) }
      end

      def steps(list)
        Array(list).each_with_object({}) do |step, found|
          found.merge!(steps(step['steps']), steps([step.dig('configuration', 'fade_selection_step')].compact))
          found[step['result_name']] = step if step['result_name']
        end
      end

      def field(created, edited)
        type = created.fetch('step_type')
        field = { 'type' => STEPS.fetch(type) { raise ArgumentError, "unknown step #{type}" },
                  'required' => required?(created) }
        values = values(type, [created, edited].compact)
        values.empty? ? field : field.merge('values' => values)
      end

      # The app raises on a missing key, unless its definition or step type gives a default
      # (BehaviorDecoder._defaultStepResultValue).
      def required?(step)
        return false if step['required_feature'] || step['default_value_when_missing']

        !OPTIONAL.include?(step['step_type']) && step.fetch('options', []).none? { it['required_feature'] }
      end

      def values(type, steps)
        return enum_values(ENUMS[type]) if ENUMS[type]

        steps.flat_map { it.fetch('options', []) }.map { it.fetch('value') }.uniq
      end

      def enum_values(enum) = @snapshot.enum_values(enum) || raise(ArgumentError, "no values for #{enum}")
    end

    # What behaviors.json holds besides what the app's code and definitions give by rule. The app builds its requests
    # by hand (BehaviorEncoder.toBridgeBehavior, toBridgeBehaviorPartial, BridgeBehaviorControlLib.triggerBehavior).
    module BehaviorSchema
      ROOTS = %w[BridgeBehaviorGroupAndLights BridgeBehaviorGroupScene BridgeBehaviorWhen BridgeBehaviorWhenExtended
                 BridgeBehaviorWhenConstrained TimeSpan BridgeBehaviorFadeDuration BridgeBehaviorStreamingEndScene
                 BridgeBehaviorState BridgeBehaviorMetadata].freeze
      REQUESTS = {
        'BehaviorInstanceAdd' => {
          'origin' => 'BridgeBehavior', 'kind' => 'add',
          'fields' => {
            'script_id' => { 'type' => 'String', 'required' => true },
            'enabled' => { 'type' => 'Boolean', 'required' => true },
            'configuration' => { 'type' => 'BehaviorConfiguration', 'required' => true },
            'metadata' => { 'type' => { 'class' => 'BehaviorMetadata' }, 'required' => true },
            'migrated_from' => { 'type' => 'String', 'required' => false }
          }
        },
        'BehaviorInstanceUpdate' => {
          'origin' => 'BridgeBehavior', 'kind' => 'update',
          'fields' => {
            'enabled' => { 'type' => 'Boolean', 'required' => false },
            'configuration' => { 'type' => 'BehaviorConfiguration', 'required' => false },
            'metadata' => { 'type' => { 'class' => 'BehaviorMetadata' }, 'required' => false },
            'trigger' => { 'type' => { 'class' => 'BehaviorTrigger' }, 'required' => false }
          }
        },
        'BehaviorTrigger' => {
          'origin' => 'BridgeBehaviorTrigger', 'kind' => 'update',
          'fields' => { 'start' => { 'type' => 'Hash', 'required' => false },
                        'stop' => { 'type' => 'Hash', 'required' => false } }
        }
      }.freeze
      RESOURCES = { 'behavior_instance' => { 'update' => 'BehaviorInstanceUpdate',
                                             'create' => 'BehaviorInstanceAdd' } }.freeze
      OVERRIDES = { 'BehaviorInstance' => { 'configuration' => { 'type' => 'BehaviorConfiguration' },
                                            'state' => { 'type' => { 'class' => 'BehaviorState' } } } }.freeze

      module_function

      # @param scripts [Hash] what {BehaviorScripts#read} returns
      # @param classes [Hash{String=>Hash}] what {BehaviorClasses#read} returns
      # @return [Hash] the content of behaviors.json
      def compose(scripts:, classes:)
        { 'scripts' => scripts.fetch('scripts'), 'resources' => RESOURCES, 'overrides' => OVERRIDES,
          'classes' => classes.merge(scripts.fetch('classes'), REQUESTS).sort.to_h }
      end
    end
  end
end
