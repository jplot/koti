# frozen_string_literal: true

# Event stream payloads shaped like the bridge's.
module EventHelpers
  def light_update_message
    lights = [{ id: 'l1', type: 'light', on: { on: true } }, { id: 'l2', type: 'light', on: { on: false } }]
    container = { creationtime: '2026-10-25T10:00:00Z', id: 'c1', type: 'update', data: lights }
    "id: 1:0\ndata: #{JSON.generate([container])}\n\n"
  end
end

RSpec.configure { |config| config.include EventHelpers }
