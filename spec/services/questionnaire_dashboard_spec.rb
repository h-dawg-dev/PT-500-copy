require "rails_helper"

RSpec.describe QuestionnaireDashboard do
     def submission(email:, user: nil, answers: {}, **attributes)
          QuestionnaireResponse.create!({ user: user, email: email, questions: Questionnaire::QUESTIONS,
            answers: { "name" => "Sample Person" }.merge(answers) }.merge(attributes))
     end

     it "counts each person once and follows the latest submission, including matching legacy email" do
          member = create_user(email: "dedupe@tamu.edu")
          submission(email: member.email, answers: { "classification" => "freshman" }, created_at: 4.days.ago)
          submission(email: member.email, user: member, answers: { "classification" => "sophomore" }, created_at: 3.days.ago)
          latest = submission(email: member.email, user: member, answers: { "classification" => "junior" })
          dashboard = described_class.new
          expect(dashboard.responses).to eq([ latest ])
          expect(dashboard.total_people).to eq(1)
          expect(dashboard.distribution("classification").find { |row| row[:label] == "Junior" }).to include(count: 1, percentage: 100)
          expect(QuestionnaireResponse.count).to eq(3)
     end

     it "keeps unanswered, declined, and historical answers separate with accurate denominators" do
          submission(email: "one@tamu.edu", answers: { "transfer_student" => "prefer_not_to_answer", "email_opt_in" => "yes" })
          submission(email: "two@tamu.edu", answers: { "transfer_student" => "no" })
          submission(email: "three@tamu.edu", answers: { "transfer_student" => "legacy option", "email_opt_in" => "no" })
          dashboard = described_class.new
          expect(dashboard.email_opt_ins).to eq(1)
          expect(dashboard.percentage(1)).to eq(33)
          rows = dashboard.distribution("transfer_student").index_by { |row| row[:label] }
          expect(rows["Prefer not to answer"][:count]).to eq(1)
          expect(rows["No"][:count]).to eq(1)
          expect(rows["Not answered"][:count]).to eq(0)
          expect(rows["Other / previous format"][:count]).to eq(1)
          expect(dashboard.distribution("email_opt_in").find { |row| row[:label] == "Not answered" }[:count]).to eq(1)
     end

     it "applies search and filters consistently to both charts and displayed people" do
          first = submission(email: "avery@tamu.edu", answers: { "name" => "Avery Chen", "classification" => "junior", "email_opt_in" => "yes" })
          submission(email: "other@tamu.edu", answers: { "name" => "Someone Else", "classification" => "senior", "email_opt_in" => "no" })
          dashboard = described_class.new(filters: { q: " AVERY ", classification: "junior", email_opt_in: "yes", link_status: "unlinked" })
          expect(dashboard.responses).to eq([ first ])
          expect(dashboard.total_people).to eq(2)
          expect(dashboard.email_opt_ins).to eq(1)
          expect(dashboard.unlinked).to eq(1)
          expect(dashboard.distribution("classification").sum { |row| row[:count] }).to eq(1)
     end

     it "supports unanswered filters, recent updates, and deterministic sorting" do
          old = submission(email: "z@tamu.edu", answers: { "name" => "Zeta" }, created_at: 100.days.ago, updated_at: 40.days.ago)
          recent = submission(email: "a@tamu.edu", answers: { "name" => "Alpha" }, created_at: 60.days.ago, updated_at: 2.days.ago)
          expect(described_class.new(filters: { classification: "unanswered", sort: "name" }).responses).to eq([ recent, old ])
          expect(described_class.new.recent_updates).to eq(1)
          expect(described_class.new(filters: { sort: "newest" }).responses).to eq([ recent, old ])
     end

     it "returns safe zero counts and percentages for an empty result" do
          dashboard = described_class.new
          expect(dashboard.responses).to eq([])
          expect(dashboard.percentage(0)).to eq(0)
          expect(dashboard.email_opt_ins).to eq(0)
          expect(dashboard.distribution("classification").all? { |row| row[:count].zero? && row[:percentage].zero? }).to be(true)
     end
end
