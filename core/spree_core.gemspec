require_relative '../shared/gemspec'

Gem::Specification.new do |gem|
  Spree::Gemspec.shared(gem)

  gem.name    = 'spree_core'
  gem.summary = 'Spree Core'

  gem.add_dependency 'activemerchant',     '~> 1.44.1'
  gem.add_dependency 'acts_as_list',       '~> 0.7.2'
  gem.add_dependency 'adamantium',         '~> 0.2'
  gem.add_dependency 'awesome_nested_set', '~> 3.0.1'
  gem.add_dependency 'cancancan',          '~> 1.9.2'
  gem.add_dependency 'concord',            '~> 0.1.5'
  gem.add_dependency 'equalizer',          '~> 0.0.11'
  gem.add_dependency 'friendly_id',        '~> 5.1.0'
  gem.add_dependency 'json',               '~> 1.8.3'
  gem.add_dependency 'kaminari',           '~> 0.16.3'
  gem.add_dependency 'monetize',           '~> 1.3.1'
  gem.add_dependency 'paperclip',          '~> 4.3.1'
  gem.add_dependency 'paranoia',           '~> 2.1.4'
  gem.add_dependency 'pg',                 '~> 0.18.4'
  gem.add_dependency 'premailer-rails',    '~> 1.8.2'
  gem.add_dependency 'rails',              '~> 4.1.14'
  gem.add_dependency 'ransack',            '~> 1.6'
  gem.add_dependency 'state_machine',      '~> 1.2.0'
  gem.add_dependency 'stringex',           '~> 2.5.2'
  gem.add_dependency 'truncate_html',      '~> 0.9.2'
  gem.add_dependency 'twitter_cldr',       '~> 3.0'
  gem.add_dependency 'tzinfo-data',        '~> 1.2015.7'
end
