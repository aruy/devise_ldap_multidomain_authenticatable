RSpec.describe DeviseLdapMultidomainAuthenticatable::Authenticator do
  let(:domain) do
    DeviseLdapMultidomainAuthenticatable::DomainConfig.new(
      key: :corp,
      host: "dc1.example.local",
      auth_format: "%{login}@example.local"
    )
  end

  let(:ldap_instance) { instance_double("Net::LDAP") }
  let(:ldap_factory) { class_double("Net::LDAP", new: ldap_instance) }

  it "returns success when bind succeeds" do
    allow(ldap_instance).to receive(:bind).and_return(true)

    result = described_class.call(
      login: "nakajima",
      password: "secret",
      domain: domain,
      ldap_factory: ldap_factory
    )

    expect(result).to be_success
    expect(result.domain_key).to eq("corp")
    expect(result.bind_username).to eq("nakajima@example.local")
  end

  it "binds once with the normalized samaccountname and returns emp_id" do
    allow(ldap_instance).to receive(:bind).and_return(true)

    result = described_class.call(
      login: "1234",
      normalized_bind_login: "d1234",
      emp_id: "01234",
      password: "secret",
      domain: domain,
      ldap_factory: ldap_factory
    )

    expect(result).to be_success
    expect(result.login).to eq("d1234")
    expect(result.emp_id).to eq("01234")
    expect(result.bind_username).to eq("d1234@example.local")
    expect(ldap_factory).to have_received(:new).once
  end

  it "returns failure when bind raises an exception" do
    allow(ldap_instance).to receive(:bind).and_raise(Timeout::Error)

    result = described_class.call(
      login: "nakajima",
      password: "secret",
      domain: domain,
      ldap_factory: ldap_factory
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:exception)
    expect(result.exception_class).to eq("Timeout::Error")
  end
end
