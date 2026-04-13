require "rails/railtie"

module DeviseLdapMultidomainAuthenticatable
  class Railtie < Rails::Railtie
    initializer "devise_ldap_multidomain_authenticatable.load_config" do |app|
      config_path = app.root.join("config/ldap_multidomain.yml")
      next unless config_path.exist?

      DeviseLdapMultidomainAuthenticatable.load_config!(
        path: config_path,
        env: Rails.env,
        logger: rails_logger
      )
    end

    generators do
      require_relative "generators/install_generator"
    end

    private

    def rails_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)

      nil
    end
  end
end
