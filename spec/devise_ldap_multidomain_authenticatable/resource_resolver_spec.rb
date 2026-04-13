RSpec.describe DeviseLdapMultidomainAuthenticatable::ResourceResolver do
  let(:auth_result) do
    DeviseLdapMultidomainAuthenticatable::Result.success(
      domain_key: "corp",
      bind_username: "nakajima@example.local",
      login: "d01234",
      emp_id: "01234"
    )
  end

  it "uses the model hook when available" do
    resource = double(:resource)
    klass = Class.new do
      def self.find_for_ldap_multidomain_authentication(*)
        :stubbed
      end
    end

    allow(klass).to receive(:find_for_ldap_multidomain_authentication).and_return(resource)

    resolved = described_class.call(
      resource_class: klass,
      auth_result: auth_result,
      authentication_hash: { login: "1234", emp_id: "01234" }
    )

    expect(resolved).to eq(resource)
  end

  it "stores the successful domain on the default attribute when available" do
    resource = Struct.new(:last_authenticated_domain, :emp_id, :saved) do
      def save!
        self.saved = true
      end
    end.new(nil, nil, false)

    described_class.remember_authenticated_domain(
      resource: resource,
      auth_result: auth_result
    )

    expect(resource.last_authenticated_domain).to eq("corp")
    expect(resource.emp_id).to eq("01234")
    expect(resource.saved).to be(true)
  end

  it "finds an existing resource by emp_id before login lookup" do
    resource = double(:resource)
    klass = Class.new do
      def self.find_by(*)
      end
    end
    allow(klass).to receive(:find_by).with(emp_id: "01234").and_return(resource)

    resolved = described_class.find_existing_resource(
      resource_class: klass,
      authentication_hash: { login: "1234", emp_id: "01234" }
    )

    expect(resolved).to eq(resource)
  end

  it "does not call the post-authentication hook during preloading" do
    resource = double(:resource)
    klass = Class.new do
      def self.find_for_ldap_multidomain_authentication(*)
        raise "should not be called during preload"
      end

      def self.find_for_authentication(*)
        :stubbed
      end
    end

    allow(klass).to receive(:find_for_authentication).and_return(resource)

    resolved = described_class.find_existing_resource(
      resource_class: klass,
      authentication_hash: { login: "1234", emp_id: "01234" }
    )

    expect(resolved).to eq(resource)
  end

  it "uses custom hooks for reading and writing remembered domains" do
    resource = Class.new do
      attr_reader :stored_domain

      def initialize
        @stored_domain = "domain_b"
      end

      def last_authenticated_ldap_domain
        @stored_domain
      end

      def remember_ldap_multidomain_authentication!(auth_result)
        @stored_domain = auth_result.domain_key
      end
    end.new

    expect(
      described_class.last_authenticated_domain(resource)
    ).to eq("domain_b")

    described_class.remember_authenticated_domain(
      resource: resource,
      auth_result: auth_result
    )

    expect(resource.stored_domain).to eq("corp")
  end
end
