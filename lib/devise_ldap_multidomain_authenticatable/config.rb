require "erb"
require "yaml"
require "pathname"

module DeviseLdapMultidomainAuthenticatable
  class Config
    attr_reader :domains, :parallel, :stop_on_first_success, :max_parallelism,
                :auto_create_user, :mask_bind_username_in_logs, :overall_timeout,
                :remembered_domain_attribute, :emp_id_attribute
    attr_accessor :logger

    def self.load_file(path:, env:, logger: nil)
      raw = ERB.new(File.read(path)).result
      yaml = YAML.safe_load(raw, aliases: true) || {}
      env_config = yaml.fetch(env.to_s) do
        raise ArgumentError, "missing environment #{env.inspect} in #{path}"
      end

      new(env_config.merge("logger" => logger))
    rescue Psych::Exception => e
      raise ArgumentError, "invalid YAML in #{path}: #{e.message}"
    end

    def initialize(attributes = {})
      attrs = symbolize_keys(attributes)
      @domains = Array(attrs[:domains]).map { |domain| DomainConfig.new(domain) }
      raise ArgumentError, "at least one domain must be configured" if @domains.empty?

      @parallel = attrs.key?(:parallel) ? attrs[:parallel] : true
      @stop_on_first_success = attrs.key?(:stop_on_first_success) ? attrs[:stop_on_first_success] : true
      @max_parallelism = (attrs[:max_parallelism] || @domains.size).to_i
      @max_parallelism = 1 if @max_parallelism < 1
      @auto_create_user = attrs.key?(:auto_create_user) ? attrs[:auto_create_user] : false
      @mask_bind_username_in_logs = attrs.key?(:mask_bind_username_in_logs) ? attrs[:mask_bind_username_in_logs] : false
      @overall_timeout = attrs[:overall_timeout]
      @remembered_domain_attribute = (attrs[:remembered_domain_attribute] || :last_authenticated_domain).to_sym
      @emp_id_attribute = (attrs[:emp_id_attribute] || :emp_id).to_sym
      @logger = attrs[:logger]
    end

    private

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = value
      end
    end
  end
end
