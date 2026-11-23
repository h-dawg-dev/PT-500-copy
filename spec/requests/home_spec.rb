require "rails_helper"

RSpec.describe "Home page", type: :request do
  it "shows a sign-in prompt to visitors" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Physical Therapy Society")
    expect(response.body).to include("Sign in")
    expect(response.body).to include(%(data-app-version="#{Rails.root.join('VERSION').read.strip}"))
  end

  it "forces Clerk to return to this host after sign-in" do
    host! "pts.example.test"
    ENV["CLERK_SIGN_IN_URL"] = "https://accounts.example.test/sign-in?redirect_url=http://127.0.0.1:3000"

    get root_path

    href = Nokogiri::HTML(response.body).at("a.nav-action")&.[]("href")
    expect(href).to be_present
    params = URI.decode_www_form(URI.parse(href).query.to_s).to_h
    expect(params["redirect_url"]).to eq("http://pts.example.test")
    expect(params["sign_in_force_redirect_url"]).to eq("http://pts.example.test")
    expect(params["sign_up_force_redirect_url"]).to eq("http://pts.example.test")
  ensure
    ENV["CLERK_SIGN_IN_URL"] = "https://example.com/sign-in"
  end

  it "shows the member dashboard to signed-in members" do
    user = User.create!(
      clerk_user_id: "user_member",
      email: "member@example.com",
      first_name: "Iris",
      role: :member
    )
    sign_in_as(user)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Iris")
    expect(response.body).to include("member")
    expect(response.body).not_to include("Officer tools")
  end

  it "shows officer tools to signed-in officers" do
    user = User.create!(
      clerk_user_id: "user_officer",
      email: "officer@example.com",
      first_name: "Hudson",
      role: :officer
    )
    sign_in_as(user)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Officer tools")
    expect(response.body).to include("Post an event")
  end

  it "shows remaining total and category points on the member home page" do
    create_current_term
    officer = create_officer
    member = create_user(first_name: "Iris")
    event = Event.create!(
      title: "Clinic night",
      starts_at: 2.days.ago,
      points: 2,
      category: :professional,
      created_by: officer
    )
    Attendance.create!(event: event, user: member, recorded_by: officer)
    sign_in_as(member)

    get root_path

    expect(response.body).to include("/ 7 points earned")
    expect(response.body).to include("5 more points needed in total")
    expect(response.body).to include("1 social point still needed")
    expect(response.body).not_to include("professional point still needed")
    expect(response.body).to include("Clinic night")
  end

  it "says when a member has met the points requirement" do
    create_current_term
    officer = create_officer
    member = create_user
    professional = Event.create!(title: "PTCAS", starts_at: 3.days.ago, points: 4, category: :professional, created_by: officer)
    social = Event.create!(title: "Mixer", starts_at: 2.days.ago, points: 3, category: :social, created_by: officer)
    Attendance.create!(event: professional, user: member, recorded_by: officer)
    Attendance.create!(event: social, user: member, recorded_by: officer)
    sign_in_as(member)

    get root_path

    expect(response.body).to include("You have met the points requirement.")
    expect(response.body).not_to include("still needed")
  end

  it "does not count a previous term's points on the member home page" do
    officer = create_officer
    member = create_user
    create_term(name: "Now-home", starts_on: Date.current - 45.days, ends_on: Date.current + 45.days) unless Term.current
    old = Event.create!(title: "Old mixer-xyzz", starts_at: Time.zone.parse("2026-03-02 18:00"), points: 7, category: :social, created_by: officer)
    Attendance.create!(event: old, user: member, recorded_by: officer)
    sign_in_as(member)

    get root_path

    expect(response.body).not_to include("You have met the points requirement.")
    expect(response.body).not_to include("Old mixer-xyzz")
  end
end

RSpec.describe "Officer area", type: :request do
  it "sends members away from officer-only pages" do
    user = User.create!(
      clerk_user_id: "user_member2",
      email: "member2@example.com",
      role: :member
    )
    sign_in_as(user)

    get officer_root_path

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("officers")
  end

  it "lets officers open the officer dashboard" do
    user = User.create!(
      clerk_user_id: "user_officer2",
      email: "officer2@example.com",
      first_name: "Hudson",
      role: :officer
    )
    sign_in_as(user)

    get officer_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Officer dashboard")
  end

  it "sends visitors to sign in instead of the officer desk" do
    get officer_root_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end

  it "shows officers the next session on the desk" do
    officer = create_officer
    Event.create!(title: "Next clinic", starts_at: 2.days.from_now, created_by: officer)
    sign_in_as(officer)

    get officer_root_path

    expect(response.body).to include("Next clinic")
    expect(response.body).to include("Mark attendance")
  end
end
