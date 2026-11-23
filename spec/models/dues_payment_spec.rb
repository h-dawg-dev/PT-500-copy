require "rails_helper"

RSpec.describe DuesPayment do
     let!(:term) { create_current_term }
  let(:member) { create_user }

  it "records a payment for a member in a term" do
       officer = create_officer
    payment = described_class.create!(user: member, term: term, recorded_by: officer)
    expect(payment).to be_persisted
    expect(payment.recorded_by).to eq(officer)
  end

  it "allows only one payment per member per term" do
       described_class.create!(user: member, term: term)
    duplicate = described_class.new(user: member, term: term)
    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows the same member to pay in a different term" do
       other_term = create_term(starts_on: Date.current - 300.days, ends_on: Date.current - 200.days)
    described_class.create!(user: member, term: term)
    expect(described_class.new(user: member, term: other_term)).to be_valid
  end

  it "refuses a payment for an officer" do
       payment = described_class.new(user: create_officer, term: term)
    expect(payment).not_to be_valid
    expect(payment.errors[:user]).to include("is an officer and does not pay dues")
  end

  it "is removed along with the member" do
       described_class.create!(user: member, term: term)
    expect { member.destroy }.to change(described_class, :count).by(-1)
  end
end

RSpec.describe User, "dues" do
     let!(:term) { create_current_term }
  let(:member) { create_user }

  it "makes members owe dues and officers not" do
       expect(member.owes_dues?).to be(true)
    expect(create_officer.owes_dues?).to be(false)
  end

  it "is unpaid until a payment is recorded for the term" do
       expect(member.dues_paid?(term)).to be(false)
    DuesPayment.create!(user: member, term: term)
    expect(member.dues_paid?(term)).to be(true)
  end

  it "checks the current term when none is given" do
       expect(member.dues_paid?).to be(false)
    DuesPayment.create!(user: member, term: term)
    expect(member.dues_paid?).to be(true)
  end

  it "starts every member unpaid in a new term" do
       old_term = create_term(starts_on: Date.current - 300.days, ends_on: Date.current - 200.days)
    DuesPayment.create!(user: member, term: old_term)
    expect(member.dues_paid?(old_term)).to be(true)
    expect(member.dues_paid?(term)).to be(false)
    expect(member.dues_paid?).to be(false)
  end

  it "is never paid when no term covers today" do
       DuesPayment.create!(user: member, term: term)
    DuesPayment.delete_all
    Term.delete_all
    expect(Term.current).to be_nil
    expect(member.dues_paid?).to be(false)
  end

  it "treats someone who became an officer as not paid, even with an old record" do
       DuesPayment.create!(user: member, term: term)
    member.update!(role: :officer)
    expect(member.dues_paid?(term)).to be(false)
  end
end
