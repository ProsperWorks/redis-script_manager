lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redis/script_manager/version'

Gem::Specification.new do |spec|

  spec.name          = "redis-script_manager"
  spec.version       = Redis::ScriptManager::VERSION
  spec.platform      = Gem::Platform::RUBY

  spec.authors       = ["jhwillett"]
  spec.email         = ["jhw@prosperworks.com"]

  spec.summary       = 'Manage Lua script execution in Redis'
  spec.homepage      = 'https://github.com/ProsperWorks/redis-script_manager'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'bundler',         '~> 1.14'
  spec.add_development_dependency 'rake',            '~> 10.0'
  spec.add_development_dependency 'minitest',        '~> 5.0'
  spec.add_development_dependency 'redis',           '~> 3.2'
  spec.add_development_dependency 'redis-namespace', '~> 1.5'

end
