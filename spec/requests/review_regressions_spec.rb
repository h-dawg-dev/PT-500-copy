require "rails_helper"

RSpec.describe "Semester gaps and access revocation", type: :request do
     include ActiveSupport::Testing::TimeHelpers
     it "shows a term gap without claiming past points meet current requirements" do
          travel_to Time.zone.local(2100, 7, 1) do
               create_term(starts_on: Date.new(2100, 1, 1), ends_on: Date.new(2100, 5, 1))
               member = create_user
               event = Event.create!(title: "Old check-in history", starts_at: Time.zone.local(2100, 3, 1), points: 7)
               Attendance.create!(event: event, user: member)
               sign_in_as(member)
               get root_path
               expect(response).to have_http_status(:ok)
               expect(response.body).to include("Current term unavailable", "Your points history · All time", "Old check-in history")
               expect(response.body).not_to include("points earned", "You have met the points requirement.")
          end
     end

     it "prompts officers to arrange term setup during a semester gap" do
          travel_to Time.zone.local(2100, 7, 1) do
               sign_in_as(create_officer)
               get root_path
               expect(response.body).to include("No term covers today", "set the current term dates")
          end
     end

     it "keeps a revoked account demoted after removal from the allowlist and next sign-in" do
          allow(User).to receive(:officer_emails).and_return([ "revoked@tamu.edu" ])
          officer = User.sync_from_clerk(email_verified: true, clerk_user_id: "review_revocation", email: "revoked@tamu.edu")
          expect(officer).to be_officer
          allow(User).to receive(:officer_emails).and_return([])
          officer.update!(role: :member)
          returning = User.sync_from_clerk(email_verified: true, clerk_user_id: officer.clerk_user_id, email: officer.email)
          expect(returning).to be_member
          sign_in_as(returning)
          get officer_root_path
          expect(response).to redirect_to(root_path)
     end
end
