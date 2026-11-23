require "rails_helper"

RSpec.describe "Officer sessions", type: :request do
  it "lets an officer post a session" do
    officer = create_officer
    sign_in_as(officer)

    expect {
      post officer_events_path, params: {
        event: {
          title: "PTCAS workshop",
          location: "PEAP 202",
          starts_at: 1.week.from_now,
          points: 2,
          category: "social"
        }
      }
    }.to change(Event, :count).by(1)

    event = Event.last
    expect(response).to redirect_to(officer_event_path(event))
    expect(event.created_by).to eq(officer)
    expect(event.points).to eq(2)
    expect(event).to be_social
  end

  it "blocks members from posting sessions" do
    sign_in_as(create_user)

    expect {
      post officer_events_path, params: { event: { title: "Nope", starts_at: 1.day.from_now } }
    }.not_to change(Event, :count)

    expect(response).to redirect_to(root_path)
  end

  it "lets an officer mark and remove attendance" do
    officer = create_officer
    member = create_user(first_name: "Iris", last_name: "Klingbeil")
    event = Event.create!(title: "Meeting", starts_at: 1.day.from_now, created_by: officer)
    sign_in_as(officer)

    post officer_event_attendances_path(event), params: { user_id: member.id }

    attendance = Attendance.find_by!(event: event, user: member)
    expect(response).to redirect_to(officer_event_path(event))
    follow_redirect!
    expect(response.body).to include("Iris Klingbeil")
    expect(response.body).to include("Present")

    delete officer_event_attendance_path(event, attendance)
    expect(event.attendances).to be_empty
  end

  it "shows session notes on the officer roster" do
    officer = create_officer
    event = Event.create!(
      title: "Meeting",
      notes: "Bring PTCAS questions.",
      starts_at: 1.day.from_now,
      created_by: officer
    )
    sign_in_as(officer)

    get officer_event_path(event)

    expect(response.body).to include("Bring PTCAS questions.")
  end

  it "marks attendance as JSON without a full page reload" do
    officer = create_officer
    member = create_user(first_name: "Iris", last_name: "Klingbeil")
    event = Event.create!(title: "Meeting", starts_at: 1.day.from_now, created_by: officer)
    sign_in_as(officer)

    post officer_event_attendances_path(event), params: { user_id: member.id }, as: :json

    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json["present"]).to be true
    expect(json["name"]).to eq("Iris Klingbeil")
    expect(json["attendance_id"]).to be_present

    attendance = Attendance.find(json["attendance_id"])
    delete officer_event_attendance_path(event, attendance), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["present"]).to be false
    expect(event.attendances.reload).to be_empty
  end

  it "lets an officer update a session category and title" do
    officer = create_officer
    event = Event.create!(title: "Meeting", starts_at: 1.day.from_now, created_by: officer)
    sign_in_as(officer)

    patch officer_event_path(event), params: {
      event: { title: "PTCAS workshop", category: "professional", points: 3 }
    }

    expect(response).to redirect_to(officer_event_path(event))
    event.reload
    expect(event.title).to eq("PTCAS workshop")
    expect(event).to be_professional
    expect(event.points).to eq(3)
  end

  it "keeps a session off the board when the title is missing" do
    officer = create_officer
    sign_in_as(officer)

    expect {
      post officer_events_path, params: { event: { title: "", starts_at: 1.day.from_now } }
    }.not_to change(Event, :count)

    expect(response).to have_http_status(422)
  end

  it "lets an officer take a session off the board" do
    officer = create_officer
    event = Event.create!(title: "Meeting", starts_at: 1.day.from_now, created_by: officer)
    sign_in_as(officer)

    expect {
      delete officer_event_path(event)
    }.to change(Event, :count).by(-1)

    expect(response).to redirect_to(officer_events_path)
  end

  it "shows the category on the officer roster" do
    officer = create_officer
    event = Event.create!(
      title: "Meeting",
      category: :professional,
      starts_at: 1.day.from_now,
      created_by: officer
    )
    sign_in_as(officer)

    get officer_event_path(event)

    expect(response.body).to include("Professional")
  end

  it "shows who RSVPed on the officer roster" do
    officer = create_officer
    member = create_user(first_name: "Iris", last_name: "Klingbeil")
    event = Event.create!(title: "Meeting", starts_at: 1.day.from_now, created_by: officer)
    Rsvp.create!(event: event, user: member)
    sign_in_as(officer)

    get officer_event_path(event)

    expect(response.body).to include("Iris Klingbeil")
    expect(response.body).to include("Going")
    expect(response.body).to include("1 going")
  end


  it "blocks members from marking attendance" do
    officer = create_officer
    member = create_user
    event = Event.create!(title: "Meeting", starts_at: 1.day.from_now, created_by: officer)
    sign_in_as(member)

    expect {
      post officer_event_attendances_path(event), params: { user_id: member.id }
    }.not_to change(Attendance, :count)

    expect(response).to redirect_to(root_path)
  end
end
