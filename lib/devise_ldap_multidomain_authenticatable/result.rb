module DeviseLdapMultidomainAuthenticatable
  class Result
    attr_reader :domain_key, :bind_username, :login, :emp_id, :error, :exception_class, :exception_message

    def self.success(domain_key:, bind_username:, login:, emp_id: nil)
      new(
        success: true,
        domain_key: domain_key,
        bind_username: bind_username,
        login: login,
        emp_id: emp_id
      )
    end

    def self.failure(login:, emp_id: nil, domain_key: nil, bind_username: nil, error: :invalid, exception: nil)
      new(
        success: false,
        domain_key: domain_key,
        bind_username: bind_username,
        login: login,
        emp_id: emp_id,
        error: error,
        exception_class: exception&.class&.name,
        exception_message: exception&.message
      )
    end

    def initialize(success:, login:, emp_id: nil, domain_key: nil, bind_username: nil, error: nil, exception_class: nil, exception_message: nil)
      @success = success
      @domain_key = domain_key
      @bind_username = bind_username
      @login = login
      @emp_id = emp_id
      @error = error
      @exception_class = exception_class
      @exception_message = exception_message
    end

    def success?
      @success
    end

    def failure?
      !success?
    end
  end
end
