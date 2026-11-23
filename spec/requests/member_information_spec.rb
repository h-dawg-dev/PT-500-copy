require "rails_helper"

RSpec.describe "Updating member information", type: :request do
     let(:member) { create_user(first_name: "Iris", last_name: "Klingbeil", email: "information@tamu.edu", major: "Biology", tshirt_size: "M") }
     let(:answers) do
          {
            name: "Iris Klingbeil", email: "information@tamu.edu", classification: "senior", major: "Kinesiology",
            transfer_student: "no", first_generation: "prefer_not_to_answer", tshirt_size: "L", email_opt_in: "yes"
          }
     end

     before do
          QuestionnaireResponse.create!(user: member, email: member.email, questions: Questionnaire::QUESTIONS,
            answers: { "name" => "Iris Klingbeil", "email" => member.email, "classification" => "junior" })
          sign_in_as(member)
     end

     def save_information(questionnaire = answers)
          patch profile_path, params: { questionnaire: questionnaire }
          member.reload
     end

     it "saves the intake answers and the account's copy with one save" do
          save_information

          expect(response).to redirect_to(profile_path)
          expect(response).to have_http_status(:see_other)
          expect(member).to have_attributes(major: "Kinesiology", tshirt_size: "L")
          expect(member.latest_questionnaire_response.answers).to include("classification" => "senior", "major" => "Kinesiology", "tshirt_size" => "L")
          follow_redirect!
          expect(response.body).to include("Your information was updated.", "Kinesiology")
     end

     it "updates the existing intake rather than duplicating it on repeated saves" do
          existing = member.latest_questionnaire_response

          expect {
               2.times { save_information(answers.merge(email_opt_in: "no")) }
          }.not_to change(QuestionnaireResponse, :count)

          expect(existing.reload.answers["email_opt_in"]).to eq("no")
     end

     it "renders a saved baseline and native navigation so unsaved browser Back and reload can be guarded" do
          get edit_profile_path

          page = Nokogiri::HTML(response.body)
          expect(page.at_css("body")["data-turbo"]).to eq("false")
          expect(page.at_css("meta[name='turbo-visit-control']")["content"]).to eq("reload")
          form = page.at_css("form[data-controller='unsaved-changes']")
          baseline = JSON.parse(form["data-unsaved-changes-saved-value"])
          expect(baseline).to include("questionnaire[major]" => "Biology", "questionnaire[classification]" => "junior")
          expect(form.at_css("[data-unsaved-changes-target='banner']")["hidden"]).not_to be_nil
          expect(form.at_css("dialog[data-unsaved-changes-target='dialog']").text).to include("Leave without saving?", "Keep editing", "Discard changes and leave")
     end

     it "covers every form field in the saved baseline" do
          member.latest_questionnaire_response.update!(answers: { "expected_graduation" => "Fall 2028", "classification" => "wizard" })

          get edit_profile_path

          form = Nokogiri::HTML(response.body).at_css("form[data-controller='unsaved-changes']")
          baseline = JSON.parse(form["data-unsaved-changes-saved-value"])
          fields = form.css("input[type='text'], input[type='email'], input[type='radio'], select").map { |field| field["name"] }.uniq
          expect(baseline.keys).to match_array(fields)
          expect(baseline).to include("questionnaire[expected_graduation][semester]" => "Fall", "questionnaire[expected_graduation][year]" => "2028")
          expect(baseline["questionnaire[classification]"]).to eq("")
     end

     it "keeps the saved baseline and the entered answers when a save is rejected" do
          save_information(answers.merge(major: "K" * (User::MAJOR_MAX_LENGTH + 1), classification: "freshman"))

          expect(response).to have_http_status(:unprocessable_entity)
          form = Nokogiri::HTML(response.body).at_css("form[data-controller='unsaved-changes']")
          expect(JSON.parse(form["data-unsaved-changes-saved-value"])["questionnaire[major]"]).to eq("Biology")
          expect(form.at_css("input[name='questionnaire[classification]'][checked]")["value"]).to eq("freshman")
          expect(form.at_css(".alert").text).to include("Nothing was changed", "Major is too long")
     end

     it "leaves both sections unchanged when the account cannot be saved" do
          existing = member.latest_questionnaire_response
          original = existing.attributes

          save_information(answers.merge(major: "K" * (User::MAJOR_MAX_LENGTH + 1)))

          expect(response).to have_http_status(:unprocessable_entity)
          expect(member).to have_attributes(major: "Biology", tshirt_size: "M")
          expect(existing.reload.attributes).to eq(original)
     end

     it "rolls back the account if the intake record cannot be saved" do
          allow_any_instance_of(QuestionnaireResponse).to receive(:save) do |submission|
               submission.errors.add(:base, "Intake could not be saved")
               false
          end

          save_information

          expect(response).to have_http_status(:unprocessable_entity)
          expect(member).to have_attributes(major: "Biology", tshirt_size: "M")
          expect(response.body).to include("Intake could not be saved")
          expect(Nokogiri::HTML(response.body).at("input[name='questionnaire[major]']")["value"]).to eq("Kinesiology")
     end

     it "supports leaving every optional answer unanswered" do
          save_information(name: "Iris Klingbeil", email: member.email)

          expect(member.latest_questionnaire_response.answers).to eq("name" => "Iris Klingbeil", "email" => member.email)
          expect(member).to have_attributes(major: nil, tshirt_size: nil)
     end

     it "claims only the signed-in member's legacy intake and ignores ownership parameters" do
          member.questionnaire_responses.delete_all
          legacy = QuestionnaireResponse.create!(email: member.email, questions: [], answers: {})
          other = create_user
          other_intake = QuestionnaireResponse.create!(user: other, email: other.email, questions: [], answers: { classification: "freshman" })
          original = other_intake.attributes

          expect {
               save_information(answers.merge(id: other_intake.id, user_id: other.id, role: "officer"))
          }.not_to change(QuestionnaireResponse, :count)

          expect(legacy.reload.user).to eq(member)
          expect(legacy.answers).not_to have_key("role")
          expect(other_intake.reload.attributes).to eq(original)
          expect(member).to be_member
     end

     it "leaves the rest of the account and the class year alone" do
          member.update!(class_year: 2030)
          untouched = %w[ clerk_user_id email first_name last_name role class_year created_at ]
          before = member.attributes.slice(*untouched)

          save_information(answers.merge(expected_graduation: { semester: "Spring", year: Date.current.year + 2 }, role: "officer", first_name: "Root"))

          expect(member.attributes.slice(*untouched)).to eq(before)
     end
end
