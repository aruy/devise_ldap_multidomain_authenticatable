require "rspec"
require "tmpdir"
require "logger"
require "active_support/core_ext/hash/slice"

require_relative "../lib/devise_ldap_multidomain_authenticatable"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before do
    DeviseLdapMultidomainAuthenticatable.reset_config!
  end
end
