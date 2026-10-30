# frozen_string_literal: true

require_relative '../../../schema/extract/java_names'

RSpec.describe Schema::Extract::JavaNames do
  it 'qualifies an imported class whose name holds a $' do
    source = "package defpackage;\n\nimport demo.media.Caputre$CaptureRequest;\n"

    expect(described_class.qualify('Caputre$CaptureRequest', source)).to eq('demo.media.Caputre$CaptureRequest')
  end
end
