module DeviseLdapMultidomainAuthenticatable
  class ResourceResolver
    def self.call(...)
      new(...).call
    end

    def self.find_existing_resource(resource_class:, authentication_hash:, emp_id_attribute: :emp_id)
      # 認証前 lookup は remembered domain を知るための事前解決に使います。
      new(
        resource_class: resource_class,
        auth_result: nil,
        authentication_hash: authentication_hash,
        auto_create_user: false,
        emp_id_attribute: emp_id_attribute
      ).send(:find_resource)
    end

    def self.remember_authenticated_domain(resource:, auth_result:, remembered_domain_attribute: :last_authenticated_domain, emp_id_attribute: :emp_id)
      return unless resource
      return unless auth_result&.success?

      # アプリ側で独自保存したい場合は hook に全面的に委ねられるようにします。
      if resource.respond_to?(:remember_ldap_multidomain_authentication!)
        resource.remember_ldap_multidomain_authentication!(auth_result)
      elsif resource.respond_to?(:"#{remembered_domain_attribute}=")
        resource.public_send(:"#{remembered_domain_attribute}=", auth_result.domain_key)
      end

      # emp_id は独立して同期します。
      # domain 保存をアプリ hook に委ねても、社員番号の正規化だけは gem 側で維持しやすくするためです。
      sync_emp_id(resource, auth_result, emp_id_attribute)
      persist_resource(resource)
    end

    def self.last_authenticated_domain(resource, remembered_domain_attribute: :last_authenticated_domain)
      return unless resource

      if resource.respond_to?(:last_authenticated_ldap_domain)
        resource.last_authenticated_ldap_domain
      elsif resource.respond_to?(remembered_domain_attribute)
        resource.public_send(remembered_domain_attribute)
      end
    end

    def initialize(resource_class:, auth_result:, authentication_hash:, auto_create_user: false, emp_id_attribute: :emp_id)
      @resource_class = resource_class
      @auth_result = auth_result
      @authentication_hash = symbolize_keys(authentication_hash)
      @auto_create_user = auto_create_user
      @emp_id_attribute = emp_id_attribute.to_sym
    end

    def call
      # 既存ユーザー優先で解決し、許可されている場合のみ自動作成します。
      resource = find_resource
      return resource if resource
      return unless auto_create_user

      create_resource
    end

    private

    attr_reader :resource_class, :auth_result, :authentication_hash, :auto_create_user, :emp_id_attribute

    def find_resource
      # 正規化後の emp_id が最も安定した識別子なので最初に見ます。
      resource = find_by_emp_id
      return resource if resource

      # 認証前と認証後で lookup 方針を分けたいアプリ向けの hook です。
      if auth_result.nil? && resource_class.respond_to?(:find_for_ldap_multidomain_resource)
        return resource_class.find_for_ldap_multidomain_resource(authentication_hash)
      end

      if auth_result.nil?
        return resource_class.find_for_authentication(authentication_hash) if resource_class.respond_to?(:find_for_authentication)

        return
      end

      # 認証後 hook では domain_key や emp_id を含む auth_result を渡します。
      if resource_class.respond_to?(:find_for_ldap_multidomain_authentication)
        resource_class.find_for_ldap_multidomain_authentication(auth_result, authentication_hash)
      else
        resource_class.find_for_authentication(authentication_hash)
      end
    end

    def create_resource
      # 自動作成は最小限に留め、認証キーと正規化済み emp_id だけを初期値にします。
      attributes = default_attributes
      if resource_class.respond_to?(:create!)
        resource_class.create!(attributes)
      else
        resource = resource_class.new(attributes)
        resource.save! if resource.respond_to?(:save!)
        resource
      end
    end

    def default_attributes
      keys = if resource_class.respond_to?(:authentication_keys)
               Array(resource_class.authentication_keys)
             else
               authentication_hash.keys
             end

      attributes = keys.each_with_object({}) do |key, memo|
        memo[key.to_sym] = authentication_hash[key.to_sym] if authentication_hash.key?(key.to_sym)
      end

      # 新規作成時も正規化済み emp_id と整合するようにします。
      attributes[emp_id_attribute] = auth_result.emp_id if auth_result&.emp_id
      attributes
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end

    def find_by_emp_id
      emp_id = authentication_hash[:emp_id]
      return unless emp_id
      return unless resource_class.respond_to?(:find_by)

      resource_class.find_by(emp_id_attribute => emp_id)
    end

    def self.persist_resource(resource)
      if resource.respond_to?(:save!)
        resource.save!
      elsif resource.respond_to?(:save)
        resource.save
      end
    end

    def self.sync_emp_id(resource, auth_result, emp_id_attribute)
      return unless auth_result&.emp_id
      writer = :"#{emp_id_attribute}="
      return unless resource.respond_to?(writer)
      return if resource.respond_to?(emp_id_attribute) && resource.public_send(emp_id_attribute) == auth_result.emp_id

      # すでに同じ値なら触らず、差分があるときだけ上書きします。
      resource.public_send(writer, auth_result.emp_id)
    end
  end
end
