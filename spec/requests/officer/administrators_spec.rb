require "rails_helper"

RSpec.describe "Admin management", type: :request do
     let!(:admin) { create_officer(first_name: "Alex", email: "alex@tamu.edu") }
     let!(:member) { create_user(first_name: "Morgan", email: "morgan@tamu.edu") }

     context "as an existing admin" do
          before { sign_in_as(admin) }

          it "links to admin management from the officer dashboard" do
               get officer_root_path

               expect(response.body).to include("Manage admins", officer_administrators_path)
          end

          it "lists registered people with their access and a promotion form only for members" do
               get officer_administrators_path

               expect(response).to have_http_status(:ok)
               page = Nokogiri::HTML(response.body)
               expect(page.at_css("form[action='#{officer_administrator_path(member)}'] input[name='_method']")["value"]).to eq("patch")
               expect(page.at_css("form[action='#{officer_administrator_path(member)}']")["data-turbo-confirm"]).to include(member.email)
               expect(page.at_css("form[action='#{officer_administrator_path(admin)}']")).to be_nil
               expect(response.body).to include("Admin (officer)", "Member", "Your account")
          end

          it "grants officer access to an existing member and shows confirmation" do
               expect { patch officer_administrator_path(member) }.to change { member.reload.role }.from("member").to("officer")

               expect(response).to redirect_to(officer_administrators_path)
               expect(response).to have_http_status(:see_other)
               follow_redirect!
               expect(response.body).to include("Morgan Klingbeil now has admin access.", "Already an admin")
          end

          it "lets a newly promoted admin grant access to someone else" do
               patch officer_administrator_path(member)
               sign_in_as(member.reload)
               another_member = create_user

               expect { patch officer_administrator_path(another_member) }.to change { another_member.reload.role }.to("officer")
          end

          it "keeps the granted role on subsequent Clerk syncs without an email allowlist" do
               allow(User).to receive(:officer_emails).and_return([])
               patch officer_administrator_path(member)

               synced = User.sync_from_clerk(email_verified: true, clerk_user_id: member.clerk_user_id, email: member.email)

               expect(synced).to be_officer
          end

          it "only changes the role of the selected account, ignoring submitted account fields" do
               original_attributes = member.attributes.except("role", "updated_at")
               untouched = create_user

               patch officer_administrator_path(member), params: {
                 user: { id: untouched.id, email: "stolen@tamu.edu", clerk_user_id: "stolen", role: "member", first_name: "Changed" }
               }

               expect(member.reload).to be_officer
               expect(member.attributes.except("role", "updated_at")).to eq(original_attributes)
               expect(untouched.reload).to be_member
          end

          it "safely accepts a repeated promotion without creating accounts or demoting anyone" do
               expect { 2.times { patch officer_administrator_path(admin) } }.not_to change(User, :count)

               expect(admin.reload).to be_officer
               expect(member.reload).to be_member
          end

          it "returns not found for an unknown account" do
               expect { patch officer_administrator_path(id: User.maximum(:id) + 1) }.not_to change(User, :count)

               expect(response).to have_http_status(:not_found)
          end

          it "keeps the organization exception at member level and rejects direct promotion" do
               organization = create_user(email: User::ORGANIZATION_MEMBER_EMAIL)
               get officer_administrators_path
               page = Nokogiri::HTML(response.body)
               expect(page.at_css("form[action='#{officer_administrator_path(organization)}']")).to be_nil
               expect(response.body).to include("Organization account · member access only")

               expect { patch officer_administrator_path(organization), as: :json }.not_to change { organization.reload.role }
               expect(response).to redirect_to(officer_administrators_path)
               expect(flash[:alert]).to include("must remain member")
          end

          it "preserves attendance and adjustments when a promoted member stops earning points" do
               term = create_current_term
               event = Event.create!(title: "Session", starts_at: Time.current, points: 3, created_by: admin)
               attendance = Attendance.create!(event: event, user: member, recorded_by: admin)
               adjustment = PointAdjustment.create!(user: member, term: term, recorded_by: admin, points: 2, category: :general, reason: "Correction")
               expect(member.points_earned(term)).to eq(5)

               patch officer_administrator_path(member)

               expect(member.reload.points_earned(term)).to eq(0)
               expect(member.attendances).to include(attendance)
               expect(member.point_adjustments).to include(adjustment)
          end
     end

     context "as a member" do
          before { sign_in_as(member) }

          it "denies access to the list" do
               get officer_administrators_path

               expect(response).to redirect_to(root_path)
               expect(response.body).not_to include(admin.email)
          end

          it "prevents self-promotion and promotion of other members, including JSON requests" do
               another_member = create_user

               [ member, another_member ].each do |target|
                    expect { patch officer_administrator_path(target), params: { role: "officer" }, as: :json }.not_to change { target.reload.role }
                    expect(response).to redirect_to(root_path)
               end
          end

          it "does not offer admin management on the member home page" do
               get root_path

               expect(response.body).not_to include(officer_administrators_path)
          end
     end

     context "when signed out" do
          before { sign_in_as(nil) }

          it "requires sign-in to see accounts" do
               get officer_administrators_path

               expect(response).to have_http_status(:redirect)
               expect(response.body).not_to include(admin.email, member.email)
          end

          it "requires sign-in to grant admin access" do
               expect { patch officer_administrator_path(member) }.not_to change { member.reload.role }

               expect(response).to have_http_status(:redirect)
          end
     end
end
