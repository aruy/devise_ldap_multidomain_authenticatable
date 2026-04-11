require "rails/generators"

module DeviseLdapMultidomainAuthenticatable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :model_name, type: :string, default: "users", desc: "Migration target table name"
      class_option :remembered_domain_attribute, type: :string, default: "last_authenticated_domain",
                   desc: "Attribute name used to store the last successful domain"

      def copy_initializer
        template "initializer.rb.tt", "config/initializers/devise_ldap_multidomain_authenticatable.rb"
      end

      def copy_config
        template "ldap_multidomain.yml.tt", "config/ldap_multidomain.yml"
      end

      def create_migration
        template "remembered_domain_migration.rb.tt", migration_destination
      end

      private

      def migration_destination
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        "db/migrate/#{timestamp}_add_#{remembered_domain_attribute}_to_#{model_name}.rb"
      end

      def model_name
        options["model_name"]
      end

      def remembered_domain_attribute
        options["remembered_domain_attribute"]
      end

      def migration_class_name
        "AddLdapMultidomainAuthFieldsTo#{camelize(model_name)}"
      end

      def camelize(value)
        value.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
