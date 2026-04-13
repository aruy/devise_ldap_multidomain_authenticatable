require "rails/generators"
require "devise_ldap_multidomain_authenticatable/generators/install_generator"
require "tmpdir"

RSpec.describe DeviseLdapMultidomainAuthenticatable::Generators::InstallGenerator do
  it "builds a migration path with the default attribute and table" do
    generator = described_class.new([], {}, destination_root: Dir.mktmpdir)

    allow(Time).to receive_message_chain(:now, :utc, :strftime).and_return("20260412013000")

    expect(generator.send(:migration_destination))
      .to eq("db/migrate/20260412013000_add_ldap_multidomain_auth_fields_to_users.rb")
    expect(generator.send(:migration_class_name)).to eq("AddLdapMultidomainAuthFieldsToUsers")
  end

  it "supports custom model and attribute names" do
    generator = described_class.new(
      [],
      { model_name: "members", remembered_domain_attribute: "ldap_domain_key" },
      destination_root: Dir.mktmpdir
    )

    allow(Time).to receive_message_chain(:now, :utc, :strftime).and_return("20260412013000")

    expect(generator.send(:migration_destination))
      .to eq("db/migrate/20260412013000_add_ldap_multidomain_auth_fields_to_members.rb")
    expect(generator.send(:migration_class_name)).to eq("AddLdapMultidomainAuthFieldsToMembers")
  end

  it "can generate a unique emp_id index when requested" do
    destination_root = Dir.mktmpdir
    generator = described_class.new(
      [],
      { unique_emp_id: true },
      destination_root: destination_root
    )

    allow(Time).to receive_message_chain(:now, :utc, :strftime).and_return("20260412013000")

    generator.create_migration

    expect(generator.send(:unique_emp_id?)).to eq(true)
    migration = File.read(File.join(destination_root, "db/migrate/20260412013000_add_ldap_multidomain_auth_fields_to_users.rb"))
    expect(migration).to include("add_index :users, :emp_id, unique: true")
  end
end
