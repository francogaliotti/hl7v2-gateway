# frozen_string_literal: true

require_relative 'lib/hl7_gateway/version'

Gem::Specification.new do |spec|
  spec.name = 'hl7_gateway'
  spec.version = Hl7Gateway::VERSION
  spec.authors = ['Franco Galiotti']
  spec.email = ['francogaliotti@gmail.com']

  spec.summary = 'Bridge between HL7 v2 (MLLP) systems and JSON HTTP APIs.'
  spec.description = 'Receives HL7 v2 messages over MLLP, converts them to JSON, forwards them to a configurable ' \
                     'HTTP API and converts the JSON answer back into an HL7 v2 response.'
  spec.homepage = 'https://github.com/francogaliotti/hl7v2-gateway'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*.rb', 'bin/*', 'README.md', 'LICENSE']
  spec.bindir = 'bin'
  spec.executables = %w[hl7-gateway hl7-send hl7-to-json json-to-hl7]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby-hl7', '~> 1.4'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
