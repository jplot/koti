# frozen_string_literal: true

# The koti-plan format: a home's walls, openings and rooms, level by level, in centimetres.
module KotiPlan
  # The JSON Schema of the format, which the front reads too.
  SCHEMA_PATH = Rails.root.join('../catalog/koti-plan.schema.json')

  # The validator built once from {SCHEMA_PATH}.
  SCHEMER = JSONSchemer.schema(SCHEMA_PATH)

  class << self
    # Checks a document against the schema, then against what the schema cannot say:
    # unique ids, and each opening's sill below its head and its head within the level.
    #
    # @param document [Object] a parsed JSON document
    # @return [Array<String>] one message per problem, each naming its JSON pointer; empty when the plan is valid
    def errors(document)
      found = SCHEMER.validate(document).map { it.fetch('error') }
      found.empty? ? level_errors(document.fetch('levels')) : found
    end

    private

    def level_errors(levels)
      repeated_ids(levels, '/levels') +
        levels.each_with_index.flat_map { |level, index| errors_in(level, "/levels/#{index}") }
    end

    def errors_in(level, path)
      %w[walls openings rooms].flat_map { repeated_ids(level.fetch(it), "#{path}/#{it}") } +
        level.fetch('openings').each_with_index.flat_map do |opening, index|
          opening_errors(opening, level.fetch('height'), "#{path}/openings/#{index}")
        end
    end

    def repeated_ids(items, path)
      seen = Set.new
      items.each_with_index.filter_map do |item, index|
        id = item.fetch('id')
        "value at `#{path}/#{index}/id` repeats the id #{id}" unless seen.add?(id)
      end
    end

    def opening_errors(opening, height, path)
      sill = opening.fetch('sill')
      head = opening.fetch('head')
      [
        ("value at `#{path}/sill` must be below the head (#{head})" if sill >= head),
        ("value at `#{path}/head` must not exceed the level height (#{height})" if head > height)
      ].compact
    end
  end
end
