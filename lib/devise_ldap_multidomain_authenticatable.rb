require "devise"
require "net/ldap"
require "active_support"
require "active_support/concern"
require "active_support/core_ext/hash/slice"
require "active_support/core_ext/object/blank"

require_relative "devise_ldap_multidomain_authenticatable/version"
require_relative "devise_ldap_multidomain_authenticatable/result"
require_relative "devise_ldap_multidomain_authenticatable/normalized_login"
require_relative "devise_ldap_multidomain_authenticatable/domain_config"
require_relative "devise_ldap_multidomain_authenticatable/config"
require_relative "devise_ldap_multidomain_authenticatable/authenticator"
require_relative "devise_ldap_multidomain_authenticatable/parallel_authenticator"
require_relative "devise_ldap_multidomain_authenticatable/resource_resolver"

module DeviseLdapMultidomainAuthenticatable
  class << self
    attr_writer :config

    def config
      @config ||= default_config
    end

    def configure
      yield(config)
    end

    def load_config!(path:, env:, logger: nil)
      self.config = Config.load_file(path: path, env: env, logger: logger)
    end

    def reset_config!
      @config = nil
    end

    private

    def default_config
      Config.new(
        "domains" => [
          {
            "key" => "default",
            "host" => "localhost",
            "auth_format" => "%{login}"
          }
        ]
      )
    end
  end
end

require "devise/models/ldap_multidomain_authenticatable"
require "devise/strategies/ldap_multidomain_authenticatable"
require_relative "devise_ldap_multidomain_authenticatable/railtie" if defined?(Rails::Railtie)

Devise.add_module(
  :ldap_multidomain_authenticatable,
  strategy: true,
  controller: :sessions,
  model: "devise/models/ldap_multidomain_authenticatable"
)
