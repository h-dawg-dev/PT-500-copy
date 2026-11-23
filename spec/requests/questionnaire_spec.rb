require "rails_helper"

RSpec.describe "Questionnaire", type: :request do
  let(:member) { create_user(first_name: "Alex", last_name: "Rivera", email: "alex@tamu.edu") }
  let(:answers) do
    {
      name: "Alex Rivera",
      email: " Alex.R@TAMU.edu ",
      classification: "freshman",
      transfer_student: "no",
      first_generation: "yes",
      email_opt_in: "yes"
    }
  end

  def response_page
    Nokogiri::HTML(response.body)
  end

  def create_response(user = member)
    QuestionnaireResponse.create!(user: user, email: user.email, questions: QuestionnaireController::QUESTIONS, answers: answers)
  end

  it "requires sign-in to open the form" do
    get questionnaire_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end

  it "requires sign-in to submit an answer" do
    expect { post questionnaire_path, params: { questionnaire: answers } }
      .not_to change(QuestionnaireResponse, :count)

    expect(response).to be_redirect
  end

  it "calls itself the intake form and introduces the demographic questions" do
    sign_in_as(member)

    get questionnaire_path

    expect(response_page.at("h1").text).to eq("Member Intake Form")
    expect(response.body).not_to match(/>[^<]*questionnaire[^<]*</i)
    expect(response.body.index("Demographic Information (Optional)")).to be < response.body.index("What is your classification?")
    expect(response.body.index("TAMU Email")).to be < response.body.index("Demographic Information (Optional)")
    expect(response_page.css(".questionnaire .question-card").size).to eq(Questionnaire::QUESTIONS.size)
  end

  it "saves and links a submission to the signed-in member" do
    sign_in_as(member)

    expect { post questionnaire_path, params: { questionnaire: answers } }
      .to change(QuestionnaireResponse, :count).by(1)

    saved = QuestionnaireResponse.last
    expect(saved.user).to eq(member)
    expect(saved.email).to eq("alex.r@tamu.edu")
    expect(saved.answers).to include("name" => "Alex Rivera", "classification" => "freshman", "first_generation" => "yes")
    expect(saved.questions.map { |question| question["key"] }).to include("name", "email_opt_in")
    expect(response).to redirect_to(profile_path)
    expect(flash[:notice]).to include("intake form was received")
  end

  it "sends a member who already submitted to their information page" do
    create_response
    sign_in_as(member)

    get questionnaire_path

    expect(response).to redirect_to(profile_path)
    follow_redirect!
    expect(response.body).to include("My information", "What is your classification?")
  end

  it "sends the edit link to the update page" do
    create_response
    sign_in_as(member)

    get questionnaire_path(edit: 1)

    expect(response).to redirect_to(edit_profile_path)
  end

  it "does not create a second response for the same member" do
    create_response
    sign_in_as(member)

    expect { post questionnaire_path, params: { questionnaire: answers.merge(name: "Alex Updated") } }
      .not_to change(QuestionnaireResponse, :count)

    expect(response).to redirect_to(profile_path)
    expect(flash[:alert]).to include("already submitted")
  end

  describe "the compatibility endpoint for previously opened forms" do
    it "lets a member correct an existing response without creating a duplicate" do
      existing = create_response
      sign_in_as(member)

      expect {
        patch questionnaire_path, params: { questionnaire: answers.merge(classification: "senior", email_opt_in: "no") }
      }.not_to change(QuestionnaireResponse, :count)

      expect(response).to redirect_to(profile_path)
      expect(existing.reload.answers).to include("classification" => "senior", "email_opt_in" => "no")
      expect(flash[:notice]).to include("intake answers were updated")
    end

    it "creates the intake record when an older page saves answers" do
      sign_in_as(member)

      expect {
        patch questionnaire_path, params: { questionnaire: { classification: "senior", email_opt_in: "yes" } }
      }.to change(QuestionnaireResponse, :count).by(1)

      saved = QuestionnaireResponse.last
      expect(saved.user).to eq(member)
      expect(saved.answers).to include("name" => "Alex Rivera", "email" => "alex@tamu.edu", "classification" => "senior")
      expect(response).to redirect_to(profile_path)
    end

    it "clears an intake answer the older form sent blank" do
      existing = create_response
      sign_in_as(member)

      patch questionnaire_path, params: { questionnaire: {
        classification: "", transfer_student: "", first_generation: "", email_opt_in: ""
      } }

      expect(existing.reload.answers).to eq("name" => "Alex Rivera", "email" => "alex@tamu.edu")
    end

    it "keeps newer answers an older form never sent" do
      member.update!(major: "Biology", tshirt_size: "M")
      existing = create_response
      existing.update!(answers: existing.answers.merge("expected_graduation" => "Fall 2028"))
      sign_in_as(member)

      patch questionnaire_path, params: { questionnaire: { classification: "senior" } }

      expect(member.reload).to have_attributes(major: "Biology", tshirt_size: "M")
      expect(existing.reload.answers).to include("classification" => "senior", "expected_graduation" => "Fall 2028")
    end

    it "claims a legacy submission when the member updates it" do
      legacy = QuestionnaireResponse.create!(email: member.email, questions: QuestionnaireController::QUESTIONS, answers: answers)
      sign_in_as(member)

      patch questionnaire_path, params: { questionnaire: answers.merge(classification: "junior") }

      expect(legacy.reload.user).to eq(member)
      expect(legacy.answers["classification"]).to eq("junior")
    end
  end

  it "treats an older anonymous submission with the same email as complete" do
    legacy = QuestionnaireResponse.create!(email: member.email, questions: QuestionnaireController::QUESTIONS, answers: answers)
    sign_in_as(member)

    get questionnaire_path

    expect(response).to redirect_to(profile_path)
    expect(legacy.reload.user).to be_nil

    get questionnaire_path(edit: 1)
    expect(response).to redirect_to(edit_profile_path)
  end

  it "rejects a submission missing a required answer and keeps the other answers" do
    sign_in_as(member)

    expect { post questionnaire_path, params: { questionnaire: answers.merge(name: " ") } }
      .not_to change(QuestionnaireResponse, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Please answer every required question.")
    form = response_page
    expect(form.at("#questionnaire_email")["value"]).to eq("Alex.R@TAMU.edu")
    expect(form.at("input[name='questionnaire[classification]'][checked]")["value"]).to eq("freshman")
    expect(form.at("input[name='questionnaire[first_generation]'][checked]")["value"]).to eq("yes")
    expect(form.at("#questionnaire_name")["aria-invalid"]).to eq("true")
  end

  it "rejects an invalid email" do
    sign_in_as(member)

    expect { post questionnaire_path, params: { questionnaire: answers.merge(email: "not-an-email") } }
      .not_to change(QuestionnaireResponse, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    form = response_page
    expect(form.at("#questionnaire_name")["value"]).to eq("Alex Rivera")
    expect(form.at("#questionnaire_email")["value"]).to eq("not-an-email")
    expect(form.at("input[name='questionnaire[transfer_student]'][checked]")["value"]).to eq("no")
    expect(form.at("#questionnaire_email")["aria-describedby"]).to eq("questionnaire_email_error")
  end

  it "drops unknown keys and options that are not on the list" do
    sign_in_as(member)

    post questionnaire_path, params: { questionnaire: answers.merge(classification: "wizard", role: "officer") }

    saved = QuestionnaireResponse.last
    expect(saved.answers).not_to have_key("classification")
    expect(saved.answers).not_to have_key("role")
  end

  it "starts empty except for the signed-in member's email" do
    sign_in_as(member)

    get questionnaire_path

    form = response_page
    expect(form.at("#questionnaire_email")["value"]).to eq("alex@tamu.edu")
    expect(form.at("#questionnaire_name")["value"]).to be_blank
    expect(form.at("#questionnaire_major")["value"]).to be_blank
    expect(form.css("input[type='radio'][checked]")).to be_empty
    expect(form.css("select option[selected]")).to be_empty
  end

  it "lets a picked choice be cleared instead of offering a leave unanswered option" do
    sign_in_as(member)

    get questionnaire_path

    radios = response_page.css("input[type='radio']")
    expect(response.body).not_to include("Leave unanswered")
    expect(radios.map { |radio| radio["data-action"] }.uniq).to eq([ "click->radio-toggle#toggle" ])
    expect(radios.map { |radio| radio["value"] }).not_to include("")
  end

  it "accepts skipping optional questions and declining background answers" do
    sign_in_as(member)

    post questionnaire_path, params: { questionnaire: answers.merge(
      classification: "", transfer_student: "prefer_not_to_answer", first_generation: "", email_opt_in: ""
    ) }
    expect(response).to redirect_to(profile_path)
    expect(QuestionnaireResponse.last.answers).to eq(
      "name" => "Alex Rivera", "email" => "Alex.R@TAMU.edu", "transfer_student" => "prefer_not_to_answer"
    )
  end

  it "handles an entirely missing form with editable required-answer feedback" do
    sign_in_as(member)

    expect { post questionnaire_path }.not_to change(QuestionnaireResponse, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Please answer every required question.")
  end

  describe "major and T-shirt size" do
    before { sign_in_as(member) }

    it "are optional and copied onto the account" do
      post questionnaire_path, params: { questionnaire: answers.merge(major: "  Allied   Health ", tshirt_size: "L") }

      expect(member.reload).to have_attributes(major: "Allied Health", tshirt_size: "L")
    end

    it "only offer the listed sizes" do
      get questionnaire_path
      sizes = response_page.css("select[name='questionnaire[tshirt_size]'] option").map(&:text)
      expect(sizes).to eq([ "Choose a size", *User::TSHIRT_SIZES ])

      post questionnaire_path, params: { questionnaire: answers.merge(tshirt_size: "XXXXL") }
      expect(member.reload.tshirt_size).to be_nil
    end

    it "keep what is already on the account when skipped on the first submission" do
      member.update!(major: "Biology", tshirt_size: "M")

      post questionnaire_path, params: { questionnaire: answers }

      expect(member.reload).to have_attributes(major: "Biology", tshirt_size: "M")
    end

    it "save nothing when the major is too long" do
      post questionnaire_path, params: { questionnaire: answers.merge(major: "K" * (User::MAJOR_MAX_LENGTH + 1)) }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Major is too long")
      expect(QuestionnaireResponse.count).to eq(0)
      expect(member.reload.major).to be_nil
    end
  end

  describe "expected graduation" do
    let(:year) { Date.current.year + 1 }

    before { sign_in_as(member) }

    it "offers every semester and the years from now on" do
      get questionnaire_path

      form = response_page
      semesters = form.css("select[name='questionnaire[expected_graduation][semester]'] option").map(&:text)
      years = form.css("select[name='questionnaire[expected_graduation][year]'] option").map(&:text)
      expect(semesters).to eq([ "Choose a semester", "Spring", "Summer", "Fall" ])
      expect(years.second).to eq(Date.current.year.to_s)
    end

    it "saves the semester and year together" do
      post questionnaire_path, params: { questionnaire: answers.merge(expected_graduation: { semester: "Fall", year: year }) }

      expect(QuestionnaireResponse.last.answers).to include("expected_graduation" => "Fall #{year}")
    end

    it "keeps the picks when the form is shown again" do
      post questionnaire_path, params: { questionnaire: answers.merge(name: " ", expected_graduation: { semester: "Summer", year: year }) }

      form = response_page
      expect(form.at("select[name='questionnaire[expected_graduation][semester]'] option[selected]")["value"]).to eq("Summer")
      expect(form.at("select[name='questionnaire[expected_graduation][year]'] option[selected]")["value"]).to eq(year.to_s)
    end

    it "is optional" do
      post questionnaire_path, params: { questionnaire: answers.merge(expected_graduation: { semester: "", year: "" }) }

      expect(response).to redirect_to(profile_path)
      expect(QuestionnaireResponse.last.answers).not_to have_key("expected_graduation")
    end

    [
      { semester: "Fall", year: "" },
      { semester: "", year: Date.current.year + 1 },
      { semester: "Winter", year: Date.current.year + 1 },
      { semester: "Fall", year: "1999" },
      "Fall 2028"
    ].each do |expected_graduation|
      it "drops #{expected_graduation.inspect}" do
        post questionnaire_path, params: { questionnaire: answers.merge(expected_graduation: expected_graduation) }

        expect(QuestionnaireResponse.last.answers).not_to have_key("expected_graduation")
      end
    end
  end

  describe "the reminder" do
    before { sign_in_as(member) }

    it "links to the form from other pages until it is submitted" do
      get root_path
      expect(response_page.at(".intake-reminder a")["href"]).to eq(questionnaire_path)

      get events_path
      expect(response.body).to include("intake-reminder")

      create_response
      get root_path
      expect(response.body).not_to include("intake-reminder")
      expect(response.body).not_to include(%(href="#{questionnaire_path}"))
    end

    it "goes away once only the required questions are answered" do
      post questionnaire_path, params: { questionnaire: { name: "Alex Rivera", email: "alex@tamu.edu" } }

      get root_path

      expect(response.body).not_to include("intake-reminder")
    end

    it "stays off the form itself, even when it comes back with errors" do
      get questionnaire_path
      expect(response.body).not_to include("intake-reminder")

      post questionnaire_path, params: { questionnaire: answers.merge(name: " ") }
      expect(response.body).not_to include("intake-reminder")
    end

    it "replaces the header link and the home page card" do
      get root_path

      expect(response.body).not_to include("New member check-in", "Complete your information")
    end

    it "also reminds officers" do
      sign_in_as(create_officer)

      get root_path

      expect(response.body).to include("intake-reminder")
    end
  end

  it "does not show the form to visitors" do
    get root_path

    expect(response.body).not_to include(questionnaire_path)
    expect(response.body).not_to include("intake-reminder")
  end
end
