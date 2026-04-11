module DeviseLdapMultidomainAuthenticatable
  class DomainConfig
    REQUIRED_KEYS = %i[key host auth_format].freeze

    attr_reader :key, :host, :port, :base, :auth_format, :encryption,
                :connect_timeout, :read_timeout, :tls_options

    def initialize(attributes)
      attrs = symbolize_keys(attributes)
      missing = REQUIRED_KEYS.select { |required_key| blank?(attrs[required_key]) }
      raise ArgumentError, "missing keys for domain config: #{missing.join(', ')}" if missing.any?

      @key = attrs[:key].to_s
      @host = attrs[:host]
      @port = (attrs[:port] || 389).to_i
      @base = attrs[:base]
      @auth_format = attrs[:auth_format]
      @tls_options = symbolize_keys(attrs[:tls_options] || {})
      @encryption = normalize_encryption(attrs[:encryption])
      @connect_timeout = attrs[:connect_timeout]
      @read_timeout = attrs[:read_timeout]
    end

    def build_bind_username(login)
      format(auth_format, login: login)
    rescue KeyError => e
      raise ArgumentError, "invalid auth_format for domain #{key}: #{e.message}"
    end

    def ldap_options(bind_username, password)
      options = {
        host: host,
        port: port,
        auth: {
          method: :simple,
          username: bind_username,
          password: password
        }
      }
      options[:base] = base if base
      options[:connect_timeout] = connect_timeout if connect_timeout
      options[:read_timeout] = read_timeout if read_timeout
      options[:encryption] = encryption if encryption
      options
    end

    private

    def normalize_encryption(value)
      return nil if blank?(value)

      case value.to_sym
      when :simple_tls
        { method: :simple_tls, tls_options: tls_options }
      when :start_tls
        { method: :start_tls, tls_options: tls_options }
      else
        raise ArgumentError, "unsupported encryption for domain #{key}: #{value.inspect}"
      end
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
