# frozen_string_literal: true

# Usage: ruby schema/extract/locales.rb path/to/LocalesJson.Production.json lib/miele/sdk/cloud/locales.json

require 'json'

module Schema
  module Extract
    # Reduces the sales companies the Miele app bundles (+…Bundled.LocalesJson.Production.json+ of
    # Miele.Libraries.Foundation.Platform) to what a login needs. Their feature settings, API keys among them, stay out.
    module Locales
      module_function

      # @param sales_companies [Array<Hash>] the parsed resource
      # @return [Array<Hash>] per organization: +iso+, +countries+, +rest+ host, +ciam+, +ciam_endpoints+
      def trim(sales_companies)
        sales_companies.map do |company|
          { 'iso' => company.dig('organization', 'iso'), 'countries' => company['countries'].map { it['iso'] },
            'rest' => company.dig('mcsConfig', 'dnsNames').find { it['type'] == 'rest' }&.fetch('host'),
            'ciam' => company.dig('ciam', 'active') == true, 'ciam_endpoints' => endpoints(company) }
        end
      end

      # @param company [Hash]
      # @return [Hash{String=>String}] the authorize, token and logout addresses
      def endpoints(company)
        company.dig('ciam', 'endpoints').to_a.to_h { [it['type'], it['uri']] }.slice('authorize', 'token', 'logout')
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  source, target = ARGV
  File.write(target, "#{JSON.pretty_generate(Schema::Extract::Locales.trim(JSON.parse(File.read(source))))}\n")
end
