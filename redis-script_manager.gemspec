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
  spec.required_ruby_version = '>= 2.1'

  spec.add_runtime_dependency 'redis' # tested from 3.0 through 4.1
end
