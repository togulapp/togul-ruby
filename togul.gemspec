Gem::Specification.new do |s|
  s.name        = 'togul'
  s.version     = '2.4.0'
  s.summary     = 'Ruby SDK for Togul Feature Flag Service'
  s.description = 'Client library for evaluating feature flags from a Togul server with TTL caching, retry, and fallback support.'
  s.license     = 'MIT'
  s.authors     = ['Togul']
  s.homepage    = 'https://github.com/togulapp/togul-ruby'
  s.metadata    = { 'source_code_uri' => 'https://github.com/togulapp/togul-ruby' }
  s.files       = Dir['lib/**/*.rb']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.0'

  s.add_dependency 'json'
  s.add_dependency 'net-http'
end
