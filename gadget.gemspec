# encoding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gadget/version'

Gem::Specification.new do | spec |
  spec.name          = 'gadget'
  spec.version       = Gadget::VERSION
  spec.authors       = [ 'Craig S. Cottingham' ]
  spec.email         = [ 'craig.cottingham@gmail.com' ]
  spec.summary       = %q{Some methods for getting metadata and other deep details from a PostgreSQL database.}
  spec.description   = File.read(File.join(File.dirname(__FILE__), 'README.md'))
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = [ 'lib' ]

  spec.add_dependency             'pg',       '~> 0.18.0'

  spec.add_development_dependency 'bundler',  '~> 2.1'
  spec.add_development_dependency 'rake'
end
