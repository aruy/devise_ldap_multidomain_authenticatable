RSpec.describe "remembered domain flow" do
  let(:domains) do
    [
      DeviseLdapMultidomainAuthenticatable::DomainConfig.new(
        key: :domain_a,
        host: "a.example.local",
        auth_format: "%{login}@a.example.local"
      ),
      DeviseLdapMultidomainAuthenticatable::DomainConfig.new(
        key: :domain_b,
        host: "b.example.local",
        auth_format: "%{login}@b.example.local"
      ),
      DeviseLdapMultidomainAuthenticatable::DomainConfig.new(
        key: :domain_c,
        host: "c.example.local",
        auth_format: "%{login}@c.example.local"
      )
    ]
  end

  it "tries the remembered domain first and returns immediately on success" do
    called_domains = []

    allow(DeviseLdapMultidomainAuthenticatable::Authenticator).to receive(:call) do |args|
      called_domains << args[:domain].key
      DeviseLdapMultidomainAuthenticatable::Result.success(
        domain_key: args[:domain].key,
        bind_username: "#{args[:login]}@#{args[:domain].key}.example.local",
        login: args[:login]
      )
    end

    result = DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator.call(
      login: "nakajima",
      password: "secret",
      domains: domains,
      preferred_domain_key: :domain_b
    )

    expect(result).to be_success
    expect(result.domain_key).to eq("domain_b")
    expect(called_domains).to eq(["domain_b"])
  end

  it "falls back to the remaining domains when the remembered domain fails" do
    called_domains = []

    allow(DeviseLdapMultidomainAuthenticatable::Authenticator).to receive(:call) do |args|
      called_domains << args[:domain].key
      if args[:domain].key == "domain_b"
        DeviseLdapMultidomainAuthenticatable::Result.failure(login: args[:login], domain_key: "domain_b")
      else
        DeviseLdapMultidomainAuthenticatable::Result.success(
          domain_key: args[:domain].key,
          bind_username: "#{args[:login]}@#{args[:domain].key}.example.local",
          login: args[:login]
        )
      end
    end

    result = DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator.call(
      login: "nakajima",
      password: "secret",
      domains: domains,
      preferred_domain_key: :domain_b,
      parallel: false
    )

    expect(result).to be_success
    expect(called_domains.first).to eq("domain_b")
    expect(called_domains).to include("domain_a")
    expect(called_domains.count("domain_b")).to eq(1)
  end
end
