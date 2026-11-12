require "rails_helper"

RSpec.describe ObjectRepository do
  let!(:event) { create(:catalog_event) }

  it "finds a domain object by its type id" do
    expect(described_class.find(event.tid)).to eq(event)
    expect(described_class.exists?(event.tid)).to be(true)
  end

  it "raises NotFound for unknown ids, unknown prefixes and malformed ids" do
    expect { described_class.find(TypeId.generate("event")) }.to raise_error(ObjectRepository::NotFound)
    expect { described_class.find(TypeId.generate("unicorn")) }.to raise_error(ObjectRepository::UnknownType)
    expect { described_class.find("garbage") }.to raise_error(ObjectRepository::NotFound)
    expect(described_class.exists?("garbage")).to be(false)
  end

  it "registers models declaring has_typeid" do
    expect(described_class.registered_prefixes).to include("event")
  end
end
