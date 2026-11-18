# frozen_string_literal: true

namespace :koti do
  namespace :plan do
    desc 'Print the koti plan of an architect model.json: koti:plan:from_model[PATH,LEVEL NAME]'
    task :from_model, %i[path level_name] => :environment do |_task, args|
      args.with_defaults(level_name: 'Logement')
      model = JSON.parse(File.read(args[:path]))
      puts JSON.pretty_generate(KotiPlan::FromModel.new(model, args[:level_name]).document)
    end
  end
end
