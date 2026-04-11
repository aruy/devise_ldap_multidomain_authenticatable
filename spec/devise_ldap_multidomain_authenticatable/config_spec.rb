RSpec.describe DeviseLdapMultidomainAuthenticatable::Config do
  it "loads environment-specific yaml config" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ldap_multidomain.yml")
      File.write(path, <<~YAML)
        common: &common
          port: 636
          encryption: simple_tls

        test:
          parallel: false
          domains:
            - key: corp
              host: dc1.example.local
              auth_format: "%{login}@example.local"
              <<: *common
      YAML

      config = described_class.load_file(path: path, env: :test)

      expect(config.parallel).to be(false)
      expect(config.domains.size).to eq(1)
      expect(config.domains.first.port).to eq(636)
    end
  end
end
