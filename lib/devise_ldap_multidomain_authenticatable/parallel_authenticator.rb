require "timeout"
require "thread"

module DeviseLdapMultidomainAuthenticatable
  class ParallelAuthenticator
    def self.call(...)
      new(...).call
    end

    def initialize(login:, password:, domains:, logger: nil, ldap_factory: Net::LDAP, parallel: true,
                   max_parallelism: nil, stop_on_first_success: true, overall_timeout: nil,
                   mask_bind_username_in_logs: false, preferred_domain_key: nil, normalized_bind_login: nil, emp_id: nil)
      @login = login
      @password = password
      @domains = domains
      @logger = logger
      @ldap_factory = ldap_factory
      @parallel = parallel
      @max_parallelism = max_parallelism || domains.size
      @stop_on_first_success = stop_on_first_success
      @overall_timeout = overall_timeout
      @mask_bind_username_in_logs = mask_bind_username_in_logs
      @preferred_domain_key = preferred_domain_key&.to_s
      @normalized_bind_login = normalized_bind_login || login
      @emp_id = emp_id
    end

    def call
      return failure_result(:invalid_configuration) if domains.empty?

      # 前回成功したドメインが分かっていれば、まずそこを単独で試します。
      # 当たりやすいドメインを先に引くことで、待ち時間と無駄な bind を減らします。
      preferred_result = try_preferred_domain_first
      return preferred_result if preferred_result&.success?

      remaining_domains = fallback_domains
      return preferred_result if remaining_domains.empty? && preferred_result
      return failure_result(:invalid_configuration) if remaining_domains.empty?
      return run_sequential(remaining_domains) unless parallel && remaining_domains.size > 1

      # 並列化はシンプルに保ちます。
      # 固定数の worker が Queue からドメインを取り出し、
      # 親スレッドは最初の成功結果を採用します。
      job_queue = Queue.new
      result_queue = Queue.new
      winner = Queue.new
      remaining_domains.each { |domain| job_queue << domain }

      worker_count = [[max_parallelism.to_i, 1].max, remaining_domains.size].min
      threads = Array.new(worker_count) do
        Thread.new do
          worker_loop(job_queue, result_queue, winner)
        end
      end

      success = collect_parallel_results(result_queue, threads, winner, expected_results: remaining_domains.size)
      return success if success

      failure_result(:invalid)
    ensure
      Array(threads).each { |thread| thread.join(0.05) }
    end

    private

    attr_reader :login, :password, :domains, :logger, :ldap_factory, :parallel, :max_parallelism,
                :stop_on_first_success, :overall_timeout, :mask_bind_username_in_logs, :preferred_domain_key,
                :normalized_bind_login, :emp_id

    def run_sequential(target_domains = domains)
      # preferred domain の単独試行後に残り 1 件だけになった場合や、
      # 並列実行が無効な場合は逐次で処理します。
      target_domains.each do |domain|
        result = authenticate_domain(domain)
        return result if result.success?
      end

      failure_result(:invalid)
    end

    def worker_loop(job_queue, result_queue, winner)
      loop do
        # ほかの worker が成功結果を出したら、それ以上の処理を増やしません。
        break if stop_on_first_success && !winner.empty?

        domain = job_queue.pop(true)
        result_queue << authenticate_domain(domain)
      rescue ThreadError
        break
      rescue StandardError => e
        result_queue << Result.failure(login: login, error: :exception, exception: e)
      end
    end

    def collect_parallel_results(result_queue, threads, winner, expected_results:)
      remaining = expected_results
      deadline = monotonic_deadline
      first_success = nil

      while remaining.positive?
        # overall timeout がない場合でも短い待機でこまめに結果を拾います。
        wait_time = remaining_wait_time(deadline)
        break if wait_time&.negative?

        result = pop_with_timeout(result_queue, wait_time)
        break unless result

        remaining -= 1
        if result.success?
          first_success ||= result
          if stop_on_first_success
            # winner Queue は worker への簡単な停止シグナルとして使います。
            winner << result
            return result
          end
        end
      end

      return first_success if first_success

      if deadline && remaining.positive?
        log(:warn, "ldap_multidomain_authenticatable overall timeout reached for login=#{login}")
        return failure_result(:timeout)
      end

      threads.each(&:join)
      nil
    end

    def authenticate_domain(domain)
      # どのドメインにも同じ正規化済みログインと password を渡します。
      Authenticator.call(
        login: login,
        normalized_bind_login: normalized_bind_login,
        password: password,
        domain: domain,
        logger: logger,
        ldap_factory: ldap_factory,
        mask_bind_username_in_logs: mask_bind_username_in_logs,
        emp_id: emp_id
      )
    end

    def try_preferred_domain_first
      return unless preferred_domain

      # 並列プールに入れず先に単独実行することで、
      # remembered domain がまだ正しければ最短で成功できます。
      log(:info, "ldap_multidomain_authenticatable trying remembered domain first domain=#{preferred_domain.key} login=#{login}")
      authenticate_domain(preferred_domain)
    end

    def preferred_domain
      return unless preferred_domain_key

      domains.find { |domain| domain.key == preferred_domain_key }
    end

    def fallback_domains
      # 先に試した preferred domain は fallback 側で再試行しません。
      return domains unless preferred_domain

      domains.reject { |domain| domain.key == preferred_domain.key }
    end

    def failure_result(error)
      Result.failure(login: login, emp_id: emp_id, error: error)
    end

    def monotonic_deadline
      return unless overall_timeout

      Process.clock_gettime(Process::CLOCK_MONOTONIC) + overall_timeout.to_f
    end

    def remaining_wait_time(deadline)
      return 0.1 unless deadline

      deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def pop_with_timeout(queue, wait_time)
      Timeout.timeout(wait_time) { queue.pop }
    rescue Timeout::Error
      nil
    end

    def log(level, message)
      return unless logger&.respond_to?(level)

      logger.public_send(level, message)
    end
  end
end
