# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gadget/version'

Gem::Specification.new do | spec |
  spec.name          = 'gadget'
  spec.version       = Gadget::VERSION
  spec.authors       = [ 'Craig S. Cottingham' ]
  spec.email         = [ 'craig.cottingham@gmail.com' ]
  spec.description   = %q{TODO: Write a gem description}
  spec.summary       = %q{TODO: Write a gem summary}
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = [ 'lib' ]

  spec.add_dependency             'pg',       '~> 0.17.0'

  spec.add_development_dependency 'bundler',  '~> 1.3'
  spec.add_development_dependency 'rake'
end
