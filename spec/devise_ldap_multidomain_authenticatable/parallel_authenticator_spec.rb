RSpec.describe DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator do
  let(:domains) do
    [
      DeviseLdapMultidomainAuthenticatable::DomainConfig.new(
        key: :a,
        host: "a.example.local",
        auth_format: "%{login}@a.example.local"
      ),
      DeviseLdapMultidomainAuthenticatable::DomainConfig.new(
        key: :b,
        host: "b.example.local",
        auth_format: "%{login}@b.example.local"
      )
    ]
  end

  it "returns success when one domain succeeds" do
    allow(DeviseLdapMultidomainAuthenticatable::Authenticator).to receive(:call) do |args|
      if args[:domain].key == "b"
        DeviseLdapMultidomainAuthenticatable::Result.success(
          domain_key: "b",
          bind_username: "nakajima@b.example.local",
          login: "nakajima"
        )
      else
        DeviseLdapMultidomainAuthenticatable::Result.failure(login: "nakajima", domain_key: "a")
      end
    end

    result = described_class.call(
      login: "nakajima",
      password: "secret",
      domains: domains
    )

    expect(result).to be_success
    expect(result.domain_key).to eq("b")
  end

  it "returns failure when all domains fail" do
    allow(DeviseLdapMultidomainAuthenticatable::Authenticator).to receive(:call)
      .and_return(DeviseLdapMultidomainAuthenticatable::Result.failure(login: "nakajima"))

    result = described_class.call(
      login: "nakajima",
      password: "secret",
      domains: domains
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid)
  end

  it "returns timeout failure when overall timeout elapses" do
    allow(DeviseLdapMultidomainAuthenticatable::Authenticator).to receive(:call) do
      sleep 0.1
      DeviseLdapMultidomainAuthenticatable::Result.failure(login: "nakajima")
    end

    result = described_class.call(
      login: "nakajima",
      password: "secret",
      domains: domains,
      overall_timeout: 0.01
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:timeout)
  end
end
