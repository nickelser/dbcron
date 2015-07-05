# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "dbcron/version"

Gem::Specification.new do |spec|
  spec.name          = "dbcron"
  spec.version       = DBcron::VERSION
  spec.authors       = ["Nick Elser"]
  spec.email         = ["nick.elser@gmail.com"]

  spec.summary       = "Distributed cron powered by your database"
  spec.description   = "Distributed cron powered by your database"
  spec.homepage      = "https://github.com/nickelser/dbcron"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = "~> 2.0"

  spec.add_dependency "parse-cron"
  spec.add_dependency "activerecord", "~> 4.2"
  spec.add_dependency "activesupport", "~> 4.2"
  spec.add_dependency "celluloid", "~> 0.17"

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rubocop", "~> 0.30.0"
  spec.add_development_dependency "minitest", "~> 5.5.0"
  #spec.add_development_dependency "codeclimate-test-reporter", "~> 0.4.7"
end
