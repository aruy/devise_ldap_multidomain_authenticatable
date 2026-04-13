require "spec_helper"

RSpec.describe "Devise module registration" do
  it "registers ldap_multidomain_authenticatable as a session route module" do
    expect(Devise::ALL).to include(:ldap_multidomain_authenticatable)
    expect(Devise::ROUTES[:ldap_multidomain_authenticatable]).to eq(:session)
    expect(Devise::CONTROLLERS[:ldap_multidomain_authenticatable]).to eq(:sessions)
    expect(Devise::URL_HELPERS[:session]).to include(nil, :new, :destroy)
  end
end
