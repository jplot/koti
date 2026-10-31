# frozen_string_literal: true

require_relative '../../schema/generate'

RSpec.describe Schema::Generate do
  it 'regenerates the committed files exactly' do
    expect(described_class.check(File.expand_path('../..', __dir__))).to be_empty
  end
end
