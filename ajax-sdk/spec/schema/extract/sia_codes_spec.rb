# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../schema/extract/sia_codes'

RSpec.describe Schema::Extract::SiaCodes do
  let(:source) do
    <<~PYTHON
      SIA_CODES: Final[dict[str, SIACode]] = {
          "BA": SIACode(
              code="BA",
              type="Burglary Alarm",
              description="Burglary Zone has been violated "
              "while armed",
              concerns="Zone or point",
          ),
          "CL": SIACode(
              code="CL",
              type="Closing Report",
              description="System armed, normal",
              concerns="User number",
          ),
      }
    PYTHON
  end
  let(:directory) { Dir.mktmpdir }

  after { FileUtils.remove_entry(directory) }

  it 'reads each code with the label of its type' do
    expect(described_class.rows(source)).to eq([['BA', 'Burglary Alarm'], ['CL', 'Closing Report']])
  end

  it 'refuses a source where a code does not read as the others, or where none does', :aggregate_failures do
    expect { described_class.rows(source.sub('code="CL"', 'code="XX"')) }.to raise_error(ArgumentError, /1 of 2/)
    expect { described_class.rows(source.sub('"Closing Report"', '"Closing\\tReport"')) }
      .to raise_error(ArgumentError, /1 of 2/)
    expect { described_class.rows('"""SIA Codes."""') }.to raise_error(ArgumentError, /0 of 0/)
  end

  it 'writes the codes as tab-separated lines, leaving the file as it was when a code does not read',
     :aggregate_failures do
    File.write(File.join(directory, 'sia_codes.py'), source)
    File.write(File.join(directory, 'bad.py'), source.sub('code="CL"', 'code="XX"'))
    path = File.join(directory, 'codes.tsv')
    described_class.write(File.join(directory, 'sia_codes.py'), path)
    expect { described_class.write(File.join(directory, 'bad.py'), path) }.to raise_error(ArgumentError)
    expect(File.read(path)).to eq("BA\tBurglary Alarm\nCL\tClosing Report\n")
  end
end
