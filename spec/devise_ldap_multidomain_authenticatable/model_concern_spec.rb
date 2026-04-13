RSpec.describe Devise::Models::LdapMultidomainAuthenticatable do
  it "adds a virtual password attribute" do
    klass = Class.new do
      include Devise::Models::LdapMultidomainAuthenticatable
    end

    resource = klass.new
    resource.password = "secret"

    expect(resource.password).to eq("secret")
  end
end
