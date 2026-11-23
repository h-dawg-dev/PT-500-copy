require "rails_helper"
require "rake"

RSpec.describe DemoAccountReset do
     let!(:term) { create_current_term }
     let(:officer) { create_officer }
     let(:member) { create_user(email: "demo@tamu.edu", major: "Kinesiology", tshirt_size: "M", class_year: 2027) }
     let(:other) { create_user }

     def intake_for(user, linked: true)
          QuestionnaireResponse.create!(user: linked ? user : nil, email: user.email, questions: [], answers: { major: "Biology" })
     end

     def give_member_history
          intake_for(member)
          intake_for(member, linked: false)
          past = Event.create!(title: "Session", starts_at: 1.day.ago, points: 2, category: :social, created_by: officer)
          Attendance.create!(event: past, user: member, recorded_by: officer)
          # Spends the check-in's points, so the check-in alone could not be removed.
          PointAdjustment.create!(user: member, term: term, recorded_by: officer, points: -2, category: :social, reason: "Duplicate check-in.")
          Rsvp.create!(event: Event.create!(title: "Clinic night", starts_at: 1.day.from_now, created_by: officer), user: member)
          DuesPayment.create!(user: member, term: term, recorded_by: officer)
     end

     it "removes the intake form, history and profile answers so the intake form shows again" do
          give_member_history
          other_intake = intake_for(other)
          expect(member.questionnaire_completed?).to be true

          described_class.new(member).call

          expect(member.questionnaire_completed?).to be false
          expect(member.attributes.slice("major", "tshirt_size", "class_year").values).to all(be_nil)
          expect([ member.rsvps, member.attendances, member.point_adjustments, member.dues_payments ].map(&:count)).to all(eq(0))
          expect(member).to be_member
          expect(User.exists?(member.id)).to be true
          expect(other_intake.reload.user).to eq(other)
     end

     it "reports what a reset would remove without changing anything" do
          give_member_history

          summary = described_class.new(member).summary

          expect(summary).to include(intake_responses: 2, rsvps: 1, attendances: 1, point_adjustments: 1, dues_payments: 1)
          expect(summary[:profile]).to eq("major" => "Kinesiology", "tshirt_size" => "M", "class_year" => 2027)
          expect(member.reload.questionnaire_completed?).to be true
     end

     it "can keep or grant admin access" do
          intake_for(officer)

          expect(described_class.new(officer, officer: true).call).to be_officer
          expect(described_class.new(member, officer: true).call).to be_officer
          expect(officer.questionnaire_completed?).to be false
     end

     describe "users:reset_for_demo" do
          around do |example|
               previous_application = Rake.application
               Rake.application = Rake::Application.new
               Rake::Task.define_task(:environment)
               load Rails.root.join("lib/tasks/users.rake").to_s
               example.run
          ensure
               Rake.application = previous_application
          end

          let(:task) { Rake::Task["users:reset_for_demo"] }

          def run_task(email, env = {})
               task.reenable
               previous = env.keys.to_h { |key| [ key, ENV[key] ] }
               env.each { |key, value| ENV[key] = value }
               expect { task.invoke(email) }.to output.to_stdout
          ensure
               previous&.each { |key, value| ENV[key] = value }
          end

          it "is a dry run unless APPLY=1" do
               intake_for(member)

               run_task(member.email.upcase)
               expect(member.reload.questionnaire_completed?).to be true

               run_task(member.email, "APPLY" => "1", "OFFICER" => "1")
               expect(member.reload.questionnaire_completed?).to be false
               expect(member).to be_officer
          end
     end
end
