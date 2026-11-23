require "rails_helper"

RSpec.describe "Officer questionnaire responses", type: :request do
     let(:officer) { create_officer }
  let(:member) { create_user(first_name: "Morgan", last_name: "Lee", email: "morgan@tamu.edu") }
  let(:answers) do
       {
         "name" => "Morgan Lee",
         "email" => "morgan@tamu.edu",
         "classification" => "junior",
         "transfer_student" => "prefer_not_to_answer",
         "first_generation" => "yes",
         "email_opt_in" => "yes"
       }
  end

  before do
       QuestionnaireResponse.create!(user: member, email: member.email, questions: QuestionnaireController::QUESTIONS, answers: answers)
    QuestionnaireResponse.create!(email: "legacy@tamu.edu", questions: QuestionnaireController::QUESTIONS, answers: answers.merge("name" => "Legacy Member"))
  end

  it "shows every response to officers with readable labels and account links" do
       sign_in_as(officer)

    get officer_questionnaire_responses_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Morgan Lee", "Junior", "Prefer not to answer", "Yes", "Legacy Member", "Not linked")
    expect(Nokogiri::HTML(response.body).at("a[href='#{officer_member_path(member)}']").text).to eq(member.display_name)
  end

  it "links to the page from the officer dashboard" do
       sign_in_as(officer)

    get officer_root_path

    expect(response.body).to include("Member intake forms", officer_questionnaire_responses_path)
  end

  it "shows filterable summaries and accessible chart counts" do
       sign_in_as(officer)
       get officer_questionnaire_responses_path
       expect(response.headers["Cache-Control"]).to include("no-store")
       expect(response.body).to include("Intake overview", "People with responses", "Email opt-ins", "Recently updated", "Reset filters")
       page = Nokogiri::HTML(response.body)
       expect(page.css(".intake-chart").size).to eq(2)
       expect(page.at_css("meta[name='turbo-cache-control']")["content"]).to eq("no-cache")
       expect(page.at_css("ul[aria-label='Class standing distribution']").text).to include("Junior", "100%")

       get officer_questionnaire_responses_path, params: { q: "Legacy", link_status: "unlinked" }
       page = Nokogiri::HTML(response.body)
       expect(page.css(".intake-table tbody tr").size).to eq(1)
       expect(page.at_css(".intake-table").text).to include("Legacy Member")
       expect(page.at_css(".intake-table").text).not_to include("Morgan Lee")
       expect(page.at_css(".intake-stat strong").text).to eq("1")
  end

  it "provides an empty-filter state and keeps other members' details private from ordinary users" do
       sign_in_as(officer)
       get officer_questionnaire_responses_path, params: { q: "No such member" }
       expect(response.body).to include("No intake forms match these filters")
       expect(Nokogiri::HTML(response.body).css(".intake-chart")).to be_empty

       sign_in_as(member)
       get officer_questionnaire_responses_path, params: { q: "legacy", classification: "junior" }, as: :json
       expect(response).to redirect_to(root_path)
       expect(response.body).not_to include("legacy@tamu.edu", "Intake overview")
  end

  it "paginates without changing the overview totals" do
       21.times do |index|
            QuestionnaireResponse.create!(email: "pagination#{index}@tamu.edu", questions: Questionnaire::QUESTIONS, answers: { "name" => "Person #{index}" })
       end
       sign_in_as(officer)
       get officer_questionnaire_responses_path
       page = Nokogiri::HTML(response.body)
       expect(page.css(".intake-table tbody tr").size).to eq(20)
       expect(page.at_css(".intake-stat strong").text).to eq("23")
       expect(page.at_css("nav[aria-label='Intake form pages']").text).to include("Page 1 of 2", "Next")
       get officer_questionnaire_responses_path, params: { page: 2 }
       expect(Nokogiri::HTML(response.body).css(".intake-table tbody tr").size).to eq(3)
  end

  it "shows the member's intake answers on their record" do
       sign_in_as(officer)

    get officer_member_path(member)

    expect(response.body).to include("Member intake form", "Junior", "Prefer not to answer", "First generation", "Yes")
  end

  it "shows expected graduation in place of the class year" do
       member.update!(class_year: 2031)
       member.latest_questionnaire_response.update!(answers: { "expected_graduation" => "Fall 2029" })
       sign_in_as(officer)

    get officer_member_path(member)

    expect(response.body).to include("Expected graduation", "Fall 2029")
    expect(response.body).not_to include("Graduation year", "2031")

    get officer_questionnaire_responses_path

    expect(response.body).to include("Expected graduation", "Fall 2029")
  end

  it "does not let members see questionnaire responses" do
       sign_in_as(member)

    get officer_questionnaire_responses_path

    expect(response).to redirect_to(root_path)
    expect(response.body).not_to include("Legacy Member")
  end

  it "sends visitors to sign in" do
       get officer_questionnaire_responses_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end
end
