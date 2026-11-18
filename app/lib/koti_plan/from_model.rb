# frozen_string_literal: true

module KotiPlan
  # Turns the model.json of the architect-plan scripts into a koti plan of one level.
  class FromModel
    # A door's head when the model has none: the common 204 cm frame, to correct in the produced JSON.
    DOOR_HEAD = 204
    # A window's sill when the model has none, to correct in the produced JSON.
    WINDOW_SILL = 90
    # A window's head when the model has none, to correct in the produced JSON.
    WINDOW_HEAD = 215
    # The level height when no room has a ceiling height.
    DEFAULT_HEIGHT = 250
    # The model's opening kinds and their koti-plan names.
    KINDS = { 'porte' => 'door', 'fenetre' => 'window', 'coulissante' => 'sliding' }.freeze

    # @param model [Hash{String => Object}] the parsed model.json
    # @param level_name [String] the level's name; its id is the parameterized name
    def initialize(model, level_name)
      @model = model
      @level_name = level_name
    end

    # @return [Hash{String => Object}] the koti-plan document
    def document = { 'format' => 'koti-plan', 'version' => 1, 'unit' => 'cm', 'levels' => [level] }

    private

    def level
      {
        'id' => @level_name.parameterize, 'name' => @level_name, 'elevation' => 0, 'height' => height,
        'walls' => walls, 'openings' => @model.fetch('openings').map { opening(it) },
        'rooms' => @model.fetch('rooms').map { room(it) }
      }
    end

    def height = @model.fetch('rooms').filter_map { it['hsp'] }.max || DEFAULT_HEIGHT

    def walls
      @model.fetch('walls').each_with_index.map do |(x, y, width, depth), index|
        { 'id' => "w#{index + 1}", 'footprint' => [[x, y], [x + width, y], [x + width, y + depth], [x, y + depth]] }
      end
    end

    def opening(source)
      kind = KINDS.fetch(source.fetch('kind'))
      low, high = source.fetch('at')
      {
        'id' => source.fetch('id'), 'kind' => kind, 'name' => source['label'],
        **ends(source, (low + high) / 2.0), 'depth' => high - low,
        'sill' => kind == 'window' ? WINDOW_SILL : 0,
        'head' => source['head'] || (kind == 'window' ? WINDOW_HEAD : DOOR_HEAD),
        **(kind == 'door' ? leaf(source) : {})
      }.compact
    end

    def ends(source, middle)
      along = [source.fetch('from'), source.fetch('to')]
      from, to = source.fetch('axis') == 'x' ? along.map { [it, middle] } : along.map { [middle, it] }
      { 'from' => from, 'to' => to }
    end

    # The model's `opens` counts along its axis' normal; koti-plan's `swing` along (-dy, dx), which is -x on a y axis.
    def leaf(source)
      opens = source.fetch('opens')
      { 'hinge' => source.fetch('hinge'), 'swing' => source.fetch('axis') == 'x' ? opens : -opens }
    end

    def room(source)
      {
        'id' => source.fetch('id'), 'name' => source.fetch('name'), 'outline' => source.fetch('outline'),
        'ceiling' => source['hsp'], 'finish' => source['finish'], 'label' => source['label']
      }.compact
    end
  end
end
