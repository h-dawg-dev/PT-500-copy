require "rails_helper"

RSpec.describe Rsvp, type: :model do
  it "records that a member plans to attend an upcoming session" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic night", starts_at: 1.day.from_now, created_by: officer)

    rsvp = Rsvp.create!(event: event, user: member)

    expect(rsvp).to be_persisted
    expect(event.rsvp_users).to include(member)
    expect(event.rsvped_by?(member)).to be true
    expect(event.attended_by?(member)).to be false
  end

  it "does not allow two RSVPs from the same member" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic night", starts_at: 1.day.from_now, created_by: officer)
    Rsvp.create!(event: event, user: member)

    duplicate = Rsvp.new(event: event, user: member)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include("has already been taken")
  end

  it "does not let someone RSVP after the session has started" do
    officer = create_officer
    event = Event.create!(title: "Clinic night", starts_at: 1.day.ago, created_by: officer)

    rsvp = Rsvp.new(event: event, user: create_user)
    expect(rsvp).not_to be_valid
    expect(rsvp.errors[:event]).to include("has already happened")
  end
end
