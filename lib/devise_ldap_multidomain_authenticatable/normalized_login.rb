module DeviseLdapMultidomainAuthenticatable
  class NormalizedLogin
    # raw_login はユーザーの入力値そのものです。
    # samaccountname は LDAP bind に実際に使う正規化済みの値です。
    # emp_id はアプリ側で扱いやすいよう常に 5 桁へ揃えます。
    attr_reader :raw_login, :samaccountname, :emp_id

    def self.call(login)
      new(login).call
    end

    def initialize(login)
      @raw_login = login.to_s.strip
    end

    def call
      # ユーザー入力には以下のような揺れがあります。
      # - d1234
      # - 1234
      # - d01234
      # - 01234
      # これらを以下のように正規化します。
      # - samaccountname: d1234
      # - emp_id: 01234
      digits = extract_digits(raw_login)
      emp_id = normalize_emp_id(digits)
      samaccountname = build_samaccountname(digits, emp_id)

      self.class.new_from_values(
        raw_login: raw_login,
        samaccountname: samaccountname,
        emp_id: emp_id
      )
    end

    def self.new_from_values(raw_login:, samaccountname:, emp_id:)
      instance = allocate
      instance.instance_variable_set(:@raw_login, raw_login)
      instance.instance_variable_set(:@samaccountname, samaccountname)
      instance.instance_variable_set(:@emp_id, emp_id)
      instance
    end

    private

    def extract_digits(value)
      # sAMAccountName は常に d 始まりですが、ログイン画面の入力はそうとは限りません。
      value.sub(/\Ad/i, "")
    end

    def normalize_emp_id(digits)
      # User 側の検索を安定させるため、社員番号は固定長の 5 桁で保持します。
      return unless digits.match?(/\A\d{4,5}\z/)

      digits.rjust(5, "0")
    end

    def build_samaccountname(digits, emp_id)
      # LDAP bind には実際の AD 上の形を使います。
      # - 4 桁社員番号: d1234
      # - 5 桁社員番号: d12345
      # 4 桁社員番号の 0 埋めはアプリ側保持用であり、bind には使いません。
      return raw_login.downcase if emp_id.nil?

      normalized_digits = emp_id.start_with?("0") ? emp_id.sub(/\A0+/, "") : emp_id
      normalized_digits = "0" if normalized_digits.empty?
      "d#{normalized_digits}".downcase
    end
  end
end
