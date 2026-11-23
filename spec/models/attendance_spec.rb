require "rails_helper"

RSpec.describe Attendance, type: :model do
  it "records that a member was at a session" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic night", starts_at: 1.day.from_now, created_by: officer)

    attendance = Attendance.create!(event: event, user: member, recorded_by: officer)

    expect(attendance).to be_persisted
    expect(event.attendees).to include(member)
    expect(member.attended_events).to include(event)
  end

  it "does not check the same member in twice" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic night", starts_at: 1.day.from_now, created_by: officer)
    Attendance.create!(event: event, user: member, recorded_by: officer)

    duplicate = Attendance.new(event: event, user: member, recorded_by: officer)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include("has already been taken")
  end

  it "remembers which officer recorded the check-in" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic night", starts_at: 1.day.from_now, created_by: officer)

    attendance = Attendance.create!(event: event, user: member, recorded_by: officer)

    expect(attendance.recorded_by).to eq(officer)
  end

  describe "#points_awarded" do
    let(:officer) { create_officer }
    let(:event) { Event.create!(title: "Clinic night", starts_at: 1.day.ago, points: 2, created_by: officer) }

    it "is the session's points for a member" do
      attendance = Attendance.create!(event: event, user: create_user, recorded_by: officer)

      expect(attendance.points_awarded).to eq(2)
    end

    it "is zero for an officer, whose attendance is still saved" do
      attendance = Attendance.create!(event: event, user: officer, recorded_by: officer)

      expect(attendance).to be_persisted
      expect(event.attendees).to include(officer)
      expect(attendance.points_awarded).to eq(0)
    end
  end
end
