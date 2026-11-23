require "rails_helper"

RSpec.describe Event, type: :model do
  def build_event(attrs = {})
    Event.new({
      title: "General Meeting",
      location: "PEAP 202",
      starts_at: Time.zone.parse("2026-09-22 18:00"),
      ends_at: Time.zone.parse("2026-09-22 19:00"),
      points: 1,
      notes: "Bring PTCAS questions.",
      created_by: create_officer
    }.merge(attrs))
  end

  it "is valid with a title and start time" do
    expect(build_event).to be_valid
  end

  it "is invalid without a title" do
    event = build_event(title: nil)
    expect(event).not_to be_valid
    expect(event.errors[:title]).to include("can't be blank")
  end

  it "is invalid without a start time" do
    event = build_event(starts_at: nil)
    expect(event).not_to be_valid
    expect(event.errors[:starts_at]).to include("can't be blank")
  end

  it "rejects negative points" do
    event = build_event(points: -1)
    expect(event).not_to be_valid
    expect(event.errors[:points]).to be_present
  end

  it "defaults points to zero" do
    event = Event.new(title: "Volunteer shift", starts_at: Time.zone.now)
    event.valid?
    expect(event.points).to eq(0)
  end

  it "defaults category to general" do
    event = Event.new(title: "Volunteer shift", starts_at: Time.zone.now)
    event.valid?
    expect(event.category).to eq("general")
    expect(event).to be_general
  end

  it "rejects an unknown category" do
    event = build_event
    event.category = "not-a-category"
    expect(event).not_to be_valid
    expect(event.errors[:category]).to be_present
  end

  it "does not allow the session to end before it starts" do
    event = build_event(
      starts_at: Time.zone.parse("2026-09-22 19:00"),
      ends_at: Time.zone.parse("2026-09-22 18:00")
    )
    expect(event).not_to be_valid
    expect(event.errors[:ends_at]).to include("must be after the start")
  end

  it "lists upcoming sessions from soonest to latest" do
    later = Event.create!(title: "Later", starts_at: 3.days.from_now, created_by: create_officer)
    sooner = Event.create!(title: "Sooner", starts_at: 1.day.from_now, created_by: create_officer)
    past = Event.create!(title: "Past", starts_at: 2.days.ago, created_by: create_officer)
    upcoming = Event.upcoming.to_a

    expect(upcoming).to include(sooner, later)
    expect(upcoming).not_to include(past)
    expect(upcoming.index(sooner)).to be < upcoming.index(later)
  end

  it "lists past sessions newest first" do
    older = Event.create!(title: "Older", starts_at: 5.days.ago, created_by: create_officer)
    newer = Event.create!(title: "Newer", starts_at: 1.day.ago, created_by: create_officer)
    upcoming = Event.create!(title: "Not yet", starts_at: 1.day.from_now, created_by: create_officer)
    past = Event.past.to_a

    expect(past).to include(newer, older)
    expect(past).not_to include(upcoming)
    expect(past.index(newer)).to be < past.index(older)
  end

  it "searches title, room, notes, and people who were present" do
    officer = create_officer
    member = create_user(first_name: "Iris", last_name: "Vanderford-xyzz")
    noted = Event.create!(title: "Workshop", notes: "Pack a goniometer-xyzz", starts_at: 1.day.from_now, created_by: officer)
    room = Event.create!(title: "Other", location: "Room ZEPHYR-9", starts_at: 2.days.from_now, created_by: officer)
    attended = Event.create!(title: "Clinic", starts_at: 3.days.from_now, created_by: officer)
    Event.create!(title: "Unrelated", starts_at: 4.days.from_now, created_by: officer)
    Attendance.create!(event: attended, user: member, recorded_by: officer)

    expect(Event.search("goniometer-xyzz")).to contain_exactly(noted)
    expect(Event.search("ZEPHYR-9")).to contain_exactly(room)
    expect(Event.search("Vanderford-xyzz", include_attendees: true)).to contain_exactly(attended)
  end

  it "searches by the email of someone who was present" do
    officer = create_officer
    member = create_user(email: "iris.vanderford-xyzz@example.com")
    attended = Event.create!(title: "Clinic", starts_at: 1.day.from_now, created_by: officer)
    Event.create!(title: "Unrelated", starts_at: 2.days.from_now, created_by: officer)
    Attendance.create!(event: attended, user: member, recorded_by: officer)

    expect(Event.search("iris.vanderford-xyzz@example.com", include_attendees: true)).to contain_exactly(attended)
  end

  it "returns every session when the search is blank" do
    officer = create_officer
    first = Event.create!(title: "One", starts_at: 1.day.from_now, created_by: officer)
    second = Event.create!(title: "Two", starts_at: 2.days.from_now, created_by: officer)

    expect(Event.search("   ").map(&:id)).to match_array(Event.pluck(:id))
    expect(Event.search("   ")).to include(first, second)
  end

  it "knows whether a member was checked in" do
    officer = create_officer
    member = create_user
    other = create_user
    event = Event.create!(title: "Clinic", starts_at: 1.day.from_now, created_by: officer)
    Attendance.create!(event: event, user: member, recorded_by: officer)

    expect(event.attended_by?(member)).to be true
    expect(event.attended_by?(other)).to be false
    expect(event.attended_by?(nil)).to be false
  end

  it "treats a session as upcoming when it has not started yet" do
    event = build_event(starts_at: 1.hour.from_now)
    expect(event).to be_upcoming

    event.starts_at = 1.hour.ago
    expect(event).not_to be_upcoming
  end

  it "removes check-ins when the session is taken off the board" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic", starts_at: 1.day.from_now, created_by: officer)
    Attendance.create!(event: event, user: member, recorded_by: officer)

    expect { event.destroy }.to change(Attendance, :count).by(-1)
  end

  it "puts a session in the term that covers its start time" do
    summer = create_term(name: "Summer-assign", starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2026, 7, 31))
    event = Event.create!(title: "Summer clinic", starts_at: Time.zone.parse("2026-06-15 18:00"), created_by: create_officer)

    expect(event.term).to eq(summer)
  end
end
