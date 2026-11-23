require "rails_helper"

RSpec.describe "Email access policy on existing accounts", type: :request do
     let(:email) { "returning@tamu.edu" }
     let(:clerk_user) do
          double(
            primary_email_address_id: "idn_1",
            email_addresses: [ double(id: "idn_1", email_address: email, verification: double(status: "verified")) ],
            first_name: "Alex", last_name: "Rivera"
          )
     end

     before do
          client = double(session: true, user_id: "user_signup_policy", user: clerk_user)
          allow_any_instance_of(ApplicationController).to receive(:clerk).and_return(client)
     end

     it "keeps existing valid member and officer accounts working" do
          existing = create_user(clerk_user_id: "user_signup_policy", email: email)
          get root_path
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Welcome, Alex Rivera")
          existing.update!(role: :officer)
          get officer_root_path
          expect(response).to have_http_status(:ok)
     end

     context "when a current session changes to an unauthorized email" do
          let(:email) { "changed@example.com" }

          it "denies access without updating stored profile, role, or email" do
               existing = create_officer(clerk_user_id: "user_signup_policy", email: "returning@tamu.edu")
               original = existing.attributes
               get officer_root_path
               expect(response).to have_http_status(:forbidden)
               expect(response.body).to include("This email cannot access the app")
               expect(existing.reload.attributes).to eq(original)
          end
     end

     it "lets non-TAMU accounts in only while the requirement is switched off" do
          allow(clerk_user.email_addresses.first).to receive(:email_address).and_return("outside@example.com")
          get root_path
          expect(response).to have_http_status(:forbidden)

          AppSetting.require_tamu_email = false
          get root_path
          expect(response).to have_http_status(:ok)
     end
end
