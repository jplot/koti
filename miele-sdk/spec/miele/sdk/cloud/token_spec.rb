# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Miele::Sdk::Cloud::Token do
  it 'forgets a token file that another process removes meanwhile' do
    path = File.join(Dir.mktmpdir, 'token.json')
    Miele::Sdk.configure { it.token_file = path }
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(path).and_return(true)
    expect { described_class.forget }.not_to raise_error
  end
end
