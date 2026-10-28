# frozen_string_literal: true

require_relative '../../lib/hue/sdk'
require_relative 'pairing'

module Schema
  module Extract
    # Merges the app's classes, aiohue and a capture of a bridge into the description generate.rb reads.
    class Merge
      SLOTS = { 'response' => 'added', 'update' => 'update', 'create' => 'add' }.freeze
      OPERATIONS = Hue::Sdk::Models::Operations

      # @param models [Hash{String=>Class}] hue-sdk's model of each resource type: only these types are described, with
      #   a request class for what their model can update and create
      def initialize(responses:, requests:, aiohue:, capture:, models:)
        @report = Hash.new { |report, title| report[title] = [] }
        @classes = Classes.new(responses, requests, @report)
        @pairing = Pairing.new(@classes, aiohue, @report)
        @aiohue = aiohue
        @capture = capture
        @models = models
      end

      # @return [Hash] the content of hue.json
      def schema
        resources = @models.sort.to_h { |type, model| [type, resource(type, model)] }
        @pairing.type_untyped
        @classes.untyped.each { @report['request field left untyped'] << it }
        require_fields(resources)
        { 'resources' => resources, 'classes' => @classes.all.sort.to_h }
      end

      # @return [String] what {#schema} found worth checking, one line per kind of finding
      def report = @report.map { |title, entries| "#{title} (#{entries.size}): #{entries.uniq.join(', ')}" }.join("\n")

      private

      def resource(type, model)
        name = type.split('_').map(&:capitalize).join
        resource = { 'response' => @classes.response("#{name}Added") }
        if model::Instance.include?(OPERATIONS::Update) && @classes.request?('update', "#{name}Update")
          resource['update'] = @classes.request("#{name}Update", 'update')
        end
        if model.include?(OPERATIONS::Create) && @classes.request?('add', "#{name}Add")
          resource['create'] = @classes.request("#{name}Add", 'add')
        end
        resource.each { |slot, ours| pair(type, slot, ours) }
      end

      def pair(type, slot, ours)
        theirs = @aiohue.class_for(type, SLOTS.fetch(slot))
        theirs ? @pairing.pair(ours, theirs) : @report["no aiohue class for #{slot}"] << type
      end

      def require_fields(resources)
        presence = Presence.new(@classes, resources, @capture)
        @classes.all.each do |name, cls|
          cls['fields'].each do |key, field|
            cls['kind'] == 'response' ? require_response(presence, name, key, field) : require_request(name, key, field)
          end
        end
      end

      # Every CLIP v2 resource carries its id, aiohue or not.
      def require_response(presence, name, key, field)
        by_aiohue = @pairing.required(name, key, sent: false) || (key == 'id' && presence.resource?(name))
        field['required'] = by_aiohue == true && presence.always?(name, key)
        @report['aiohue requires, live lacks'] << "#{name}.#{key}" if by_aiohue && !presence.always?(name, key)
      end

      def require_request(name, key, field)
        by_aiohue = @pairing.required(name, key, sent: true)
        @report['app requires, aiohue does not'] << "#{name}.#{key}" if field['required'] && by_aiohue == false
        field['required'] &&= by_aiohue != false
      end
    end

    # A field aiohue requires stays optional when a captured resource lacks it.
    class Presence
      def initialize(classes, resources, capture)
        @classes = classes
        @resources = resources.values.map { it['response'] }
        @seen = Hash.new(0)
        @present = Hash.new { |present, name| present[name] = Hash.new(0) }
        capture.each { observe(resources.dig(it['type'], 'response'), it) }
      end

      def resource?(name) = @resources.include?(name)

      # @return [Boolean] whether every captured resource of the class holds the field, or none was captured
      def always?(name, key) = @present[name][key] == @seen[name]

      private

      def observe(name, data)
        return unless @classes.all[name] && data.is_a?(Hash)

        @seen[name] += 1
        @classes.all[name]['fields'].each do |key, field|
          next if data[key].nil?

          @present[name][key] += 1
          observe_value(field['type'], data[key])
        end
      end

      def observe_value(type, value)
        held = Types.held(type)
        return unless held

        type['class'] ? observe(held, value) : Array(value).each { observe(held, it) }
      end
    end
  end
end
