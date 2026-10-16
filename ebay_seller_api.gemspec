# frozen_string_literal: true

require_relative 'lib/ebay_seller_api/version'

Gem::Specification.new do |spec|
  spec.name = 'ebay_seller_api'
  spec.version = EbaySellerApi::VERSION
  spec.authors = ['Your Name']
  spec.email = ['you.email@example.com']

  spec.summary = 'A Ruby SDK for eBay seller APIs: bulk XML listing feeds, Feed tasks and orders'
  spec.description = 'Sends eBay listings in bulk as LMS XML feeds, with parts of the Sell Feed and Fulfillment APIs'
  spec.homepage = 'https://github.com/gotextbooks/ebay_seller_api'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('lib/**/*') + %w[README.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'dry-configurable', '~> 1.0'
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'rubyzip', '~> 3.0'

  spec.add_development_dependency 'irb'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.80'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.0'
  spec.add_development_dependency 'webmock', '~> 3.23'
end
