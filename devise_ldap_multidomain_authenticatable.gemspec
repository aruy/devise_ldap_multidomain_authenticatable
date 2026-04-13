require_relative "lib/devise_ldap_multidomain_authenticatable/version"

Gem::Specification.new do |spec|
  spec.name = "devise_ldap_multidomain_authenticatable"
  spec.version = DeviseLdapMultidomainAuthenticatable::VERSION
  spec.authors = ["Project Contributors"]

  spec.summary = "Devise extension for parallel direct-bind LDAP authentication across multiple domains."
  spec.description = spec.summary
  spec.license = "UNLICENSED"
  spec.required_ruby_version = ">= 2.3.0"

  spec.files = Dir[
    "Gemfile",
    "Rakefile",
    "README.md",
    "lib/**/*",
    "spec/**/*"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "devise", ">= 4.7"
  spec.add_dependency "net-ldap", ">= 0.16", "< 1.0"
  spec.add_dependency "railties", ">= 5.0"

  spec.add_development_dependency "rspec", ">= 3.12"
end
