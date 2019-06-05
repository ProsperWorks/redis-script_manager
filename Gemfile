source 'https://rubygems.org'

# Development dependencies are captured in Gemfile and in
# gemfiles/*.gemfile, and managed with the gem 'appraisal', per the
# pattern:
#
#   https://github.com/jollygoodcode/jollygoodcode.github.io/issues/21

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

gemspec

group :development do
  gem 'bundler'
  gem 'appraisal',            '~> 2.2.0'
  gem 'rake',                 '~> 12.3.1'
end

group :test do
  gem 'redis-namespace',      '~> 1.5'
  gem 'minitest',             '~> 5.11.3'
  gem 'rubocop',              '~> 0.54.0'
end
