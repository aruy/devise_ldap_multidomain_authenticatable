RSpec.describe DeviseLdapMultidomainAuthenticatable::DomainConfig do
  it "builds bind usernames from auth_format" do
    domain = described_class.new(
      key: :corp,
      host: "dc1.example.local",
      auth_format: "%{login}@example.local"
    )

    expect(domain.build_bind_username("nakajima")).to eq("nakajima@example.local")
  end
end
