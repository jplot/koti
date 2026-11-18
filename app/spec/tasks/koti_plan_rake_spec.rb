# frozen_string_literal: true

require 'rake'

RSpec.describe 'koti:plan:from_model', type: :task do
  before { Rails.application.load_tasks unless Rake::Task.task_defined?('koti:plan:from_model') }

  it 'prints the plan of a model as JSON' do
    arguments = Rake::TaskArguments.new(%i[path level_name], [file_fixture('models/flat.json').to_s, 'Logement'])
    expect { Rake::Task['koti:plan:from_model'].execute(arguments) }
      .to output(a_string_including('"format": "koti-plan"').and(a_string_including('"name": "Logement"'))).to_stdout
  end
end
