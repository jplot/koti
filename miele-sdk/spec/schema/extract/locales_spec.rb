# frozen_string_literal: true

require_relative '../../../schema/extract/locales'

RSpec.describe Schema::Extract::Locales do
  let(:sales_company) do
    { 'organization' => { 'iso' => 'DK', 'name' => 'Miele A/S' }, 'active' => true,
      'countries' => [{ 'iso' => 'DK' }, { 'iso' => 'FO' }],
      'mcsConfig' => { 'dnsNames' => [{ 'type' => 'api', 'host' => 'api.example.com' },
                                      { 'type' => 'rest', 'host' => 'rest.example.com' }] },
      'ciam' => { 'active' => true,
                  'endpoints' => [{ 'type' => 'authorize', 'uri' => 'https://id.example.com/dk/authorize' },
                                  { 'type' => 'jwks', 'uri' => 'https://id.example.com/dk/jwks' }] },
      'features' => [{ 'name' => 'shop', 'config' => [{ 'key' => 'apiKey', 'value' => 'secret' }] }] }
  end

  it 'keeps the rest host, the CIAM switch and its endpoints of each organization, nothing else' do
    expect(described_class.trim([sales_company])).to eq(
      [{ 'iso' => 'DK', 'countries' => %w[DK FO], 'rest' => 'rest.example.com', 'ciam' => true,
         'ciam_endpoints' => { 'authorize' => 'https://id.example.com/dk/authorize' } }]
    )
  end
end
