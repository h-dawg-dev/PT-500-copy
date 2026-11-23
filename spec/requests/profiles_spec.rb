require "rails_helper"

RSpec.describe "Member profile", type: :request do
  let(:member) { create_user(first_name: "Iris", last_name: "Klingbeil", email: "profile@tamu.edu", major: "Biology", class_year: Date.current.year + 1, tshirt_size: "M") }

  def submit_intake(user, answers = {})
    user.questionnaire_responses.create!(
      email: user.email, questions: Questionnaire::QUESTIONS,
      answers: { "name" => "Iris Klingbeil", "email" => user.email }.merge(answers)
    )
  end

  describe "signed out" do
    it "sends visitors to sign in instead of the page or the form" do
      [ profile_path, edit_profile_path ].each do |path|
        get path

        expect(response).to be_redirect
        expect(response.location).to include("example.com/sign-in")
      end
    end

    it "does not save anything for visitors" do
      patch profile_path, params: { questionnaire: { major: "Kinesiology" } }

      expect(response).to be_redirect
      expect(response.location).to include("example.com/sign-in")
      expect(member.reload.major).to eq("Biology")
    end
  end

  describe "name menu in the header" do
    def name_menu
      Nokogiri::HTML(response.body).at("header nav details.account-menu")
    end

    it "opens from the member's name with only view and sign-out choices" do
      sign_in_as(create_user(first_name: "Justin", last_name: "Du"))

      get root_path

      expect(name_menu.at("summary").text).to eq("Justin Du")
      expect(name_menu.css("a").map(&:text)).to eq([ "View my information" ])
      expect(name_menu.at("a")["href"]).to eq(profile_path)
      expect(name_menu.at("button[data-action='clerk#signOut']").text).to eq("Sign out")
    end

    it "is on every signed-in page, for officers too" do
      sign_in_as(create_officer)

      [ root_path, events_path, profile_path, questionnaire_path, officer_root_path ].each do |path|
        get path

        expect(name_menu).to be_present
      end
    end

    it "is not shown to visitors" do
      get root_path

      expect(name_menu).to be_nil
      expect(response.body).not_to include("Sign out")
    end

    it "is the only place the dashboard shows profile details" do
      sign_in_as(member)

      get root_path

      expect(Nokogiri::HTML(response.body).at("main").text).not_to include("Biology", "T-shirt size")
    end
  end

  describe "viewing" do
    def facts
      Nokogiri::HTML(response.body).css("main dl.facts > div").to_h { |fact| [ fact.at("dt").text, fact.at("dd").text ] }
    end

    it "lists every intake question, with the major and T-shirt size among them" do
      submit_intake(member, "classification" => "grad_student", "expected_graduation" => "Fall 2028")
      sign_in_as(member)

      get profile_path

      expect(response).to have_http_status(:ok)
      expect(facts).to include(
        "First & Last Name" => "Iris Klingbeil",
        "What is your classification?" => "Graduate Student",
        "When is your expected graduation date?" => "Fall 2028",
        "What is your major?" => "Biology",
        "What is your T-shirt size?" => "M",
        "Are you a transfer student?" => "--"
      )
      expect(facts.keys).to eq(Questionnaire::QUESTIONS.map { |question| question[:prompt] })
    end

    it "does not show the class year or account section" do
      submit_intake(member)
      sign_in_as(member)

      get profile_path

      expect(response.body).not_to include("Class year", "Graduation year", member.class_year.to_s)
    end

    it "just points to the form before it is submitted" do
      sign_in_as(member)

      get profile_path

      page = Nokogiri::HTML(response.body).at("main")
      expect(facts).to be_empty
      expect(page.text).to include("You haven't filled out the Member Intake Form yet.")
      expect(page.css("a").map { |link| link["href"] }).to eq([ questionnaire_path ])
      expect(response.body).not_to include("intake-reminder")
    end

    it "has a single update link and nothing to edit on the page itself" do
      submit_intake(member)
      sign_in_as(member)

      get profile_path

      page = Nokogiri::HTML(response.body).at("main")
      expect(page.css("a[href='#{edit_profile_path}']").map(&:text)).to eq([ "Update my information" ])
      expect(page.css("form, input, select")).to be_empty
    end

    it "shows only the signed-in member, whatever id is asked for" do
      other = create_user(major: "Nursing", tshirt_size: "S")
      submit_intake(other)
      submit_intake(member)
      sign_in_as(member)

      get profile_path, params: { id: other.id, user_id: other.id }

      expect(facts["What is your major?"]).to eq("Biology")
      expect(response.body).not_to include("Nursing")
    end
  end

  describe "editing" do
    before { sign_in_as(member) }

    it "sends a member who has not submitted to the form" do
      get edit_profile_path
      expect(response).to redirect_to(questionnaire_path)

      patch profile_path, params: { questionnaire: { name: "Iris", email: member.email } }
      expect(response).to redirect_to(questionnaire_path)
      expect(QuestionnaireResponse.count).to eq(0)
    end

    it "puts every question in a single box, filled with the saved answers" do
      submit_intake(member, "classification" => "senior", "expected_graduation" => "Summer 2029", "email_opt_in" => "no")

      get edit_profile_path

      page = Nokogiri::HTML(response.body)
      expect(page.at("h1").text).to eq("My information")
      expect(page.css("main form").size).to eq(1)
      form = page.at("main form.clipboard")
      expect(form["action"]).to eq(profile_path)
      expect(form.css(".question-card").size).to eq(Questionnaire::QUESTIONS.size)
      expect(form.at("#questionnaire_name")["value"]).to eq("Iris Klingbeil")
      expect(form.at("#questionnaire_major")["value"]).to eq("Biology")
      expect(form.at("select[name='questionnaire[tshirt_size]'] option[selected]")["value"]).to eq("M")
      expect(form.at("input[name='questionnaire[classification]'][checked]")["value"]).to eq("senior")
      expect(form.at("select[name='questionnaire[expected_graduation][semester]'] option[selected]")["value"]).to eq("Summer")
      expect(form.at("select[name='questionnaire[expected_graduation][year]'] option[selected]")["value"]).to eq("2029")
      expect(form.css("input[type='submit']").map { |input| input["value"] }).to eq([ "Save information" ])
      expect(response.body).not_to include("Leave unanswered", "user[")
    end

    it "shows the account's values, even from before the form asked for them" do
      submit_intake(member)

      get edit_profile_path

      form = Nokogiri::HTML(response.body)
      expect(form.at("#questionnaire_major")["value"]).to eq("Biology")
      expect(form.at("select[name='questionnaire[tshirt_size]'] option[selected]")["value"]).to eq("M")
    end

    it "changes or clears answers, and shows them after signing in again" do
      submit_intake(member, "classification" => "senior")

      patch profile_path, params: { questionnaire: {
        name: "Iris Klingbeil", email: member.email, major: "", tshirt_size: "XL"
      } }

      expect(response).to redirect_to(profile_path)
      expect(member.reload).to have_attributes(major: nil, tshirt_size: "XL")
      expect(member.latest_questionnaire_response.answers).not_to have_key("classification")

      returning = User.sync_from_clerk(email_verified: true, clerk_user_id: member.clerk_user_id, email: member.email, first_name: "Iris", last_name: "Klingbeil")
      expect(returning).to have_attributes(major: nil, tshirt_size: "XL")
    end

    it "still requires the required answers, and keeps the old ones when rejected" do
      submit_intake(member, "classification" => "freshman")

      patch profile_path, params: { questionnaire: { name: " ", email: member.email, classification: "senior" } }

      expect(response).to have_http_status(:unprocessable_entity)
      page = Nokogiri::HTML(response.body)
      expect(page.css("main form.clipboard").size).to eq(1)
      expect(page.at("#questionnaire_name")["aria-invalid"]).to eq("true")
      expect(page.at("input[name='questionnaire[classification]'][checked]")["value"]).to eq("senior")
      expect(member.reload.latest_questionnaire_response.answers).to include("name" => "Iris Klingbeil", "classification" => "freshman")
    end

    it "rejects a T-shirt size that is not on the list by dropping it" do
      submit_intake(member)

      patch profile_path, params: { questionnaire: { name: "Iris Klingbeil", email: member.email, major: "Biology", tshirt_size: "XXXXL" } }

      expect(member.reload.tshirt_size).to be_nil
    end
  end

  describe "fields a member may not change" do
    before do
      submit_intake(member)
      sign_in_as(member)
    end

    let(:answers) { { name: "Iris Klingbeil", email: member.email, major: "Kinesiology" } }

    it "ignores role, account name, account email, and Clerk id" do
      patch profile_path, params: { questionnaire: answers.merge(role: "officer", first_name: "Root", last_name: "Admin", clerk_user_id: "user_stolen") }

      member.reload
      expect(member).to be_member
      expect(member.major).to eq("Kinesiology")
      expect(member.first_name).to eq("Iris")
      expect(member.last_name).to eq("Klingbeil")
      expect(member.clerk_user_id).not_to eq("user_stolen")
    end

    it "keeps the sign-in email when the form's email is changed" do
      patch profile_path, params: { questionnaire: answers.merge(email: "other@tamu.edu") }

      expect(member.reload.email).to eq("profile@tamu.edu")
      expect(member.latest_questionnaire_response.email).to eq("other@tamu.edu")
    end

    it "ignores semester and points" do
      officer = create_officer
      event = Event.create!(title: "Clinic night", starts_at: 2.days.ago, points: 2, created_by: officer)
      Attendance.create!(event: event, user: member, recorded_by: officer)

      expect {
        patch profile_path, params: { questionnaire: answers.merge(points: 99, points_earned: 99, semester: "Spring 2020", term_id: 0) }
      }.not_to change { [ member.reload.points_earned, Attendance.count, Term.count ] }

      expect(response).to redirect_to(profile_path)
      expect(event.reload.points).to eq(2)
    end

    it "cannot reach another member's record" do
      other = create_user(major: "Nursing", tshirt_size: "S")

      patch profile_path, params: { id: other.id, user_id: other.id, questionnaire: answers.merge(id: other.id) }

      expect(other.reload).to have_attributes(major: "Nursing", tshirt_size: "S")
      expect(member.reload.major).to eq("Kinesiology")
    end

    it "has no profile route that names a member" do
      other = create_user

      expect { Rails.application.routes.recognize_path("/profile/#{other.id}", method: :patch) }.to raise_error(ActionController::RoutingError)
      expect { Rails.application.routes.recognize_path("/users/#{other.id}", method: :patch) }.to raise_error(ActionController::RoutingError)
    end
  end
end
