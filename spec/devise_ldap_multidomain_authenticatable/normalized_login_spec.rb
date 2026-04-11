RSpec.describe DeviseLdapMultidomainAuthenticatable::NormalizedLogin do
  it "normalizes a 4-digit employee number into a single samaccountname and 5-digit emp_id" do
    result = described_class.call("1234")

    expect(result.emp_id).to eq("01234")
    expect(result.samaccountname).to eq("d1234")
  end

  it "normalizes a zero-padded 4-digit login into a 4-digit samaccountname" do
    result = described_class.call("d01234")

    expect(result.emp_id).to eq("01234")
    expect(result.samaccountname).to eq("d1234")
  end

  it "keeps a 5-digit employee number as-is" do
    result = described_class.call("12345")

    expect(result.emp_id).to eq("12345")
    expect(result.samaccountname).to eq("d12345")
  end
end
