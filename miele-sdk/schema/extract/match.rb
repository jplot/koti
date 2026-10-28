# frozen_string_literal: true

# Usage: ruby schema/extract/match.rb path/to/il CAPTURE

require 'json'
require_relative 'il'

module Schema
  module Extract
    # Ranks the app classes that could read each captured resource: those holding the most of its keys, then the fewest
    # others. Entries keyed by number, like the appliances under +/Devices/+, count as one resource.
    class Match
      NUMBER = /\A\d+\z/

      # @param app [Hash] what {Il.read} returns
      # @param capture [Hash] what {Capture.read} returns
      def initialize(app, capture)
        @app = app
        @capture = capture
      end

      # @return [Hash{String=>Array}] for each resource, up to three [app class, keys it holds, other keys it has]
      def best = resources.transform_values { rank(it) }

      def report
        best.map do |path, ranked|
          keys = resources[path]
          lines = ranked.map { |name, hit, extra| "    #{hit}/#{keys.size} +#{extra} #{name}" }
          ["#{path} #{keys.sort.inspect}", *lines].join("\n")
        end.join("\n")
      end

      private

      def resources = @resources ||= collect

      def collect
        all = Hash.new { |hash, path| hash[path] = Set.new }
        @capture.each_value { |answers| answers.each { |path, body| gather(all, path, body) } }
        all.reject { |_, keys| keys.empty? }.sort.to_h
      end

      def gather(all, path, body)
        return unless body.is_a?(Hash) && !body.key?('error')

        all[path].merge(body.keys.grep_v(NUMBER))
        body.each do |key, value|
          all["#{path} #{key.match?(NUMBER) ? '<n>' : key}"].merge(value.keys) if value.is_a?(Hash)
        end
      end

      def rank(keys)
        ranked = @app.map do |name, app_class|
          fields = app_class['fields'].keys
          [name, (keys & fields).size, (fields - keys.to_a).size]
        end
        ranked.select { it[1].positive? }.sort_by { |name, hit, extra| [-hit, extra, name] }.first(3)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts Schema::Extract::Match.new(Schema::Extract::Il.read(Dir[File.join(ARGV.fetch(0), '*.il')]),
                                  JSON.parse(File.read(ARGV.fetch(1)))).report
end
