require "rails_helper"

RSpec.describe Term, type: :model do
  def build_term(attrs = {})
    Term.new({
      name: "Fall #{SecureRandom.hex(2)}",
      starts_on: Date.new(2026, 8, 17),
      ends_on: Date.new(2026, 12, 18),
      required_points: 7,
      required_professional_points: 1,
      required_social_points: 1
    }.merge(attrs))
  end

  it "is valid with a name and date range" do
    expect(build_term).to be_valid
  end

  it "is invalid without a name" do
    term = build_term(name: nil)
    expect(term).not_to be_valid
    expect(term.errors[:name]).to include("can't be blank")
  end

  it "does not end before it starts" do
    term = build_term(starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 8, 1))
    expect(term).not_to be_valid
    expect(term.errors[:ends_on]).to include("must be on or after the start")
  end

  it "finds the term that covers a timestamp" do
    summer = create_term(name: "Summer-xyzz", starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2026, 7, 31))

    expect(Term.current(Time.zone.parse("2026-06-15 10:00"))).to eq(summer)
    expect(summer.covers?(Time.zone.parse("2026-06-15"))).to be true
    expect(summer.covers?(Time.zone.parse("2026-09-22"))).to be false
  end
end
