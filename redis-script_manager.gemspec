lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redis/script_manager/version'

Gem::Specification.new do |spec|
  spec.name          = 'redis-script_manager'
  spec.version       = Redis::ScriptManager::VERSION
  spec.platform      = Gem::Platform::RUBY
  spec.authors       = ['jhwillett']
  spec.email         = ['jhw@prosperworks.com']
  spec.license       = 'MIT'

  spec.summary       = 'Manage Lua script execution in Redis'
  spec.homepage      = 'https://github.com/ProsperWorks/redis-script_manager'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.require_paths = ['lib']

  # We use 'foo: bar' syntax liberally, not the older ':foo => bar'.
  # Possibly other Ruby 2-isms as well.
  #
  # Also, the redis gem from 4.0.0 does not support rubies < 2.2.2.
  #
  spec.required_ruby_version = ['>= 2.2.2', '< 2.7.0']       # tested to 2.6.3

  spec.add_runtime_dependency 'redis', '>= 3.0.0', '< 5.0.0' # tested to 4.1.1

  # Development dependencies are captured in Gemfile, per the pattern:
  #
  #   https://github.com/jollygoodcode/jollygoodcode.github.io/issues/21
  #
end
