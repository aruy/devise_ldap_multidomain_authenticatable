require "devise/strategies/authenticatable"

module Devise
  module Strategies
    class LdapMultidomainAuthenticatable < Authenticatable
      def valid?
        # この strategy が動く条件は、認証キーと password が揃っていることだけです。
        ldap_enabled? && normalized_login.raw_login.present? && password.present?
      end

      def authenticate!
        # lookup、bind、永続化で同じ値を使えるよう、最初に 1 回だけ正規化します。
        normalized_auth_hash = authentication_hash
        preloaded_resource = DeviseLdapMultidomainAuthenticatable::ResourceResolver.find_existing_resource(
          resource_class: mapping.to,
          authentication_hash: normalized_auth_hash,
          emp_id_attribute: configuration.emp_id_attribute
        )

        result = DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator.call(
          login: normalized_login.raw_login,
          normalized_bind_login: normalized_login.samaccountname,
          emp_id: normalized_login.emp_id,
          password: password,
          domains: configuration.domains,
          logger: logger,
          parallel: configuration.parallel,
          max_parallelism: configuration.max_parallelism,
          stop_on_first_success: configuration.stop_on_first_success,
          overall_timeout: configuration.overall_timeout,
          mask_bind_username_in_logs: configuration.mask_bind_username_in_logs,
          preferred_domain_key: remembered_domain_key_for(preloaded_resource)
        )

        unless result.success?
          fail!(failure_message_key(result))
          return
        end

        # LDAP 認証が通ってからアプリ側 resource を解決または自動作成します。
        resource = DeviseLdapMultidomainAuthenticatable::ResourceResolver.call(
          resource_class: mapping.to,
          auth_result: result,
          authentication_hash: normalized_auth_hash,
          auto_create_user: configuration.auto_create_user,
          emp_id_attribute: configuration.emp_id_attribute
        )

        unless resource
          fail!(:invalid)
          return
        end

        # 成功後に app 側で使う正規化済み情報を保存します。
        DeviseLdapMultidomainAuthenticatable::ResourceResolver.remember_authenticated_domain(
          resource: resource,
          auth_result: result,
          remembered_domain_attribute: configuration.remembered_domain_attribute,
          emp_id_attribute: configuration.emp_id_attribute
        )

        env["devise.ldap_multidomain_auth_result"] = result
        success!(resource)
      end

      private

      def configuration
        DeviseLdapMultidomainAuthenticatable.config
      end

      def ldap_enabled?
        mapping.to.devise_modules.include?(:ldap_multidomain_authenticatable)
      end

      def authentication_hash
        keys = Array(mapping.to.authentication_keys)
        auth_hash = resource_params.slice(*keys.map(&:to_s), *keys.map(&:to_sym)).each_with_object({}) do |(key, value), memo|
          memo[key.to_sym] = value
        end
        # フォームに emp_id がなくても resource 解決で使えるよう追加します。
        auth_hash[:emp_id] = normalized_login.emp_id if normalized_login.emp_id
        auth_hash
      end

      def normalized_login
        # 1 リクエスト内では正規化を 1 回だけ行うようキャッシュします。
        @normalized_login ||= DeviseLdapMultidomainAuthenticatable::NormalizedLogin.call(raw_login)
      end

      def raw_login
        # Devise は複数の authentication_key を持てますが、
        # この gem では先頭キーをログイン識別子として扱います。
        keys = Array(mapping.to.authentication_keys)
        key = keys.first
        resource_params[key.to_s] || resource_params[key]
      end

      def password
        resource_params["password"] || resource_params[:password]
      end

      def resource_params
        params.fetch(scope, params.fetch(scope.to_s, {}))
      end

      def logger
        configuration.logger || (Rails.logger if defined?(Rails) && Rails.respond_to?(:logger))
      end

      def failure_message_key(result)
        :invalid
      end

      def remembered_domain_key_for(resource)
        DeviseLdapMultidomainAuthenticatable::ResourceResolver.last_authenticated_domain(
          resource,
          remembered_domain_attribute: configuration.remembered_domain_attribute
        )
      end
    end
  end
end

Warden::Strategies.add(:ldap_multidomain_authenticatable, Devise::Strategies::LdapMultidomainAuthenticatable)
