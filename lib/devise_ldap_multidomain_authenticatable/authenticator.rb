module DeviseLdapMultidomainAuthenticatable
  class Authenticator
    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end

    def initialize(login:, password:, domain:, logger: nil, ldap_factory: Net::LDAP, mask_bind_username_in_logs: false,
                   normalized_bind_login: nil, emp_id: nil)
      @login = login
      @password = password
      @domain = domain
      @logger = logger
      @ldap_factory = ldap_factory
      @mask_bind_username_in_logs = mask_bind_username_in_logs
      @normalized_bind_login = normalized_bind_login || login
      @emp_id = emp_id
    end

    def call
      bind_username = nil
      # 各ドメインでは、正規化済みログインで 1 回だけ bind を試みます。
      bind_username = domain.build_bind_username(normalized_bind_login)
      log(:info, "ldap_multidomain_authenticatable attempting bind for domain=#{domain.key} bind_username=#{display_bind_username(bind_username)}")

      # 事前検索はせず、Net::LDAP#bind で直接本人認証を行います。
      ldap = ldap_factory.new(domain.ldap_options(bind_username, password))
      success = ldap.bind

      if success
        log(:info, "ldap_multidomain_authenticatable bind succeeded for domain=#{domain.key}")
        Result.success(domain_key: domain.key, bind_username: bind_username, login: normalized_bind_login, emp_id: emp_id)
      else
        log(:warn, "ldap_multidomain_authenticatable bind failed for domain=#{domain.key}")
        Result.failure(login: normalized_bind_login, emp_id: emp_id, domain_key: domain.key, bind_username: bind_username, error: :invalid)
      end
    rescue StandardError => e
      # timeout や socket/TLS 例外も failure result に畳み、
      # Warden 全体を落とさず扱えるようにします。
      log(:error, "ldap_multidomain_authenticatable bind error for domain=#{domain.key} exception=#{e.class} message=#{e.message}")
      Result.failure(login: login, emp_id: emp_id, domain_key: domain.key, bind_username: bind_username, error: :exception, exception: e)
    end

    private

    attr_reader :login, :password, :domain, :logger, :ldap_factory, :normalized_bind_login, :emp_id

    def log(level, message)
      return unless logger&.respond_to?(level)

      logger.public_send(level, message)
    end

    def display_bind_username(bind_username)
      # password は絶対にログへ出さず、bind_username は設定でマスク可能です。
      return "[FILTERED]" if @mask_bind_username_in_logs

      bind_username
    end
  end
end
