require "rails_helper"

RSpec.describe "Sessions board", type: :request do
  it "sends visitors to sign in" do
    get events_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end

  it "lists upcoming sessions for members and hides officer posting" do
    officer = create_officer
    Event.create!(title: "General Meeting", location: "PEAP 202", starts_at: 2.days.from_now, created_by: officer)
    Event.create!(title: "Old clinic", starts_at: 2.days.ago, created_by: officer)
    sign_in_as(create_user(first_name: "Iris"))

    get events_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("General Meeting")
    expect(response.body).to include("PEAP 202")
    expect(response.body).not_to include("Old clinic")
    expect(response.body).not_to include("Post a session")
  end

  it "filters past sessions and title search" do
    officer = create_officer
    Event.create!(title: "Volunteer shift", starts_at: 3.days.ago, created_by: officer)
    Event.create!(title: "Alumni night", starts_at: 4.days.ago, created_by: officer)
    Event.create!(title: "Volunteer later", starts_at: 2.days.from_now, created_by: officer)
    sign_in_as(create_user)

    get events_path, params: { filter: "past", q: "Volunteer" }

    expect(response.body).to include("Volunteer shift")
    expect(response.body).not_to include("Alumni night")
    expect(response.body).not_to include("Volunteer later")
  end

  it "searches notes across upcoming and past when looking at all sessions" do
    officer = create_officer
    Event.create!(title: "Old clinic", notes: "zebra-notes-99", starts_at: 2.days.ago, created_by: officer)
    Event.create!(title: "Quiet meeting", starts_at: 2.days.from_now, created_by: officer)
    sign_in_as(create_user)

    get events_path, params: { filter: "all", q: "zebra-notes-99" }

    expect(response.body).to include("Old clinic")
    expect(response.body).not_to include("Quiet meeting")
  end

  it "shows a member whether they were checked in" do
    officer = create_officer
    member = create_user(first_name: "Iris")
    event = Event.create!(title: "Clinic night", starts_at: 1.day.from_now, points: 2, created_by: officer)
    Attendance.create!(event: event, user: member, recorded_by: officer)
    sign_in_as(member)

    get event_path(event)

    expect(response.body).to include("Clinic night")
    expect(response.body).to include("Marked present")
    expect(response.body).not_to include("Mark present")
  end

  it "shows the session category on the board and the member page" do
    officer = create_officer
    event = Event.create!(
      title: "Alumni mixer",
      starts_at: 2.days.from_now,
      category: :social,
      created_by: officer
    )
    sign_in_as(create_user)

    get events_path
    expect(response.body).to include("Alumni mixer")
    expect(response.body).to include("Social")

    get event_path(event)
    expect(response.body).to include("Category")
    expect(response.body).to include("Social")
    expect(response.body).to include("Not checked in yet")
  end

  it "lets a member RSVP to an upcoming session and cancel" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Clinic night", starts_at: 2.days.from_now, created_by: officer)
    sign_in_as(member)

    post event_rsvp_path(event)
    expect(response).to redirect_to(event_path(event))
    expect(event.rsvped_by?(member)).to be true
    expect(event.attended_by?(member)).to be false

    follow_redirect!
    expect(response.body).to include("You're going")
    expect(response.body).to include("Not going")

    delete event_rsvp_path(event)
    expect(event.rsvps).to be_empty
  end

  it "does not let a member RSVP to a past session" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Old clinic", starts_at: 2.days.ago, created_by: officer)
    sign_in_as(member)

    expect {
      post event_rsvp_path(event)
    }.not_to change(Rsvp, :count)

    expect(response).to redirect_to(event_path(event))
  end
end
