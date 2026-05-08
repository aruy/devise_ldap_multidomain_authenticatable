require "logger"
RSpec.describe Devise::Strategies::LdapMultidomainAuthenticatable do
  let(:resource_klass) do
    Struct.new(:last_authenticated_domain, :emp_id, :remember_me)
  end
  let(:resource_class) do
    Class.new do
      def self.devise_modules
        [:ldap_multidomain_authenticatable]
      end

      def self.authentication_keys
        [:emp_id]
      end
    end
  end

  let(:mapping) { instance_double("Devise::Mapping", to: resource_class) }
  let(:env) do
    {
      "devise.allow_params_authentication" => true,
      "action_dispatch.request.parameters" => {
        "user" => {
          "emp_id" => "1234",
          "password" => "secret",
          "remember_me" => "1"
        }
      }
    }
  end
  let(:winning_result) do
    DeviseLdapMultidomainAuthenticatable::Result.success(
      domain_key: "corp",
      bind_username: "d1234@example.local",
      login: "d1234",
      emp_id: "01234"
    )
  end
  let(:resource) { resource_klass.new("corp", "01234") }

  before do
    allow(DeviseLdapMultidomainAuthenticatable).to receive(:config).and_return(
      DeviseLdapMultidomainAuthenticatable::Config.new(
        domains: [
          { key: :corp, host: "dc1.example.local", auth_format: "%{login}@example.local" }
        ]
      )
    )
    allow(DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator).to receive(:call).and_return(winning_result)
    allow(DeviseLdapMultidomainAuthenticatable::ResourceResolver).to receive(:call).and_return(resource)
    allow(DeviseLdapMultidomainAuthenticatable::ResourceResolver).to receive(:find_existing_resource).and_return(resource)
    allow(DeviseLdapMultidomainAuthenticatable::ResourceResolver).to receive(:remember_authenticated_domain)
    allow(Rails).to receive(:logger).and_return(Logger.new(nil)) if defined?(Rails)
  end

  it "authenticates and succeeds with the resolved resource" do
    strategy = described_class.new(env, :user)
    allow(strategy).to receive(:mapping).and_return(mapping)
    allow(strategy).to receive(:remember_me).and_call_original

    expect(strategy.valid?).to be(true)
    strategy.authenticate!

    expect(strategy.result).to eq(:success)
    expect(strategy.user).to eq(resource)
    expect(strategy).to have_received(:remember_me).with(resource)
    expect(DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator).to have_received(:call).with(
      hash_including(preferred_domain_key: "corp", normalized_bind_login: "d1234", emp_id: "01234", login: "1234")
    )
    expect(DeviseLdapMultidomainAuthenticatable::ResourceResolver).to have_received(:remember_authenticated_domain).with(
      hash_including(resource: resource, auth_result: winning_result)
    )
  end

  it "fails when ldap authentication fails" do
    strategy = described_class.new(env, :user)
    allow(strategy).to receive(:mapping).and_return(mapping)
    allow(DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator).to receive(:call).and_return(
      DeviseLdapMultidomainAuthenticatable::Result.failure(login: "1234", emp_id: "01234")
    )

    strategy.authenticate!

    expect(strategy.result).to eq(:failure)
  end
end
