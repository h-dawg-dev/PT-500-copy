require "rails_helper"

RSpec.describe "Members seeing announcements of officer point changes", type: :request do
     include ActiveSupport::Testing::TimeHelpers

     let!(:term) { create_current_term }
     let(:officer) { create_officer(first_name: "Dana", last_name: "Desk") }
     let(:member) { create_user(first_name: "Manny", last_name: "Member") }
     let(:other_member) { create_user(first_name: "Olga", last_name: "Other") }

     # Made through the officer page, the same way an officer would.
     def adjust(person, points:, category:, reason:)
          sign_in_as(officer)
          post officer_member_point_adjustments_path(person), params: { point_adjustment: { points: points, category: category, reason: reason } }
          PointAdjustment.order(:id).last
     end

     def popup
          Nokogiri::HTML(response.body).at("dialog#points_announcement")
     end

     def announced_changes
          popup.css(".announcement-list li").map { |item| item.text.squish }
     end

     def shown_ids
          popup.css("input[name='point_adjustment_ids[]']").map { |input| input["value"] }
     end

     # What the pop-up's Close button and Esc key send.
     def dismiss(ids)
          post announcement_dismissal_path, params: { point_adjustment_ids: ids }, headers: { "Accept" => "application/json" }
     end

     def clock(time)
          ApplicationController.helpers.clinic_clock(time)
     end

     describe "U12.1: a pop-up after an officer adjusts the member's points" do
          it "shows each change since the member last signed in, with amount, category, reason and date" do
               first = adjust(member, points: "2", category: "professional", reason: "Attended PTCAS night; the sign-in sheet was lost.")
               second = travel_to(1.hour.from_now) { adjust(member, points: "-1", category: "professional", reason: "Left the clinic early.") }
               sign_in_as(member)

               get root_path

               expect(popup).to be_present
               expect(popup.at("h2").text).to eq("Your points were updated")
               expect(popup.text).to include("Since you last signed in, an officer made 2 changes to your points:")
               expect(announced_changes).to eq([
                    "Added 2 professional points Reason: Attended PTCAS night; the sign-in sheet was lost. Date: #{clock(first.created_at)}",
                    "Subtracted 1 professional point Reason: Left the clinic early. Date: #{clock(second.created_at)}"
               ])
               expect(popup.css("time").map { |time| time["datetime"] }).to eq([ first.created_at.iso8601, second.created_at.iso8601 ])
          end

          it "appears on whichever page the member opens first after signing in" do
               adjust(member, points: "1", category: "social", reason: "Missed check-in at the mixer.")
               sign_in_as(member)

               [ events_path, profile_path ].each do |path|
                    get path

                    expect(announced_changes).to contain_exactly(a_string_starting_with("Added 1 social point Reason: Missed check-in at the mixer."))
               end
          end
     end

     describe "U12.2: dismissing the pop-up, and no pop-up without changes" do
          it "does not appear again once the member dismisses it, including after signing out and back in" do
               adjust(member, points: "2", category: "general", reason: "Missed check-in.")
               sign_in_as(member)
               get root_path
               ids = shown_ids

               dismiss(ids)

               expect(response).to have_http_status(:no_content)
               expect(PointAdjustment.find(ids.first).seen_at).to be_present
               [ root_path, events_path ].each do |path|
                    get path
                    expect(popup).to be_nil
               end

               sign_in_as(nil)
               get root_path
               sign_in_as(User.find(member.id))
               get root_path
               expect(popup).to be_nil
          end

          it "shows no pop-up when nothing changed since the last sign-in" do
               event = Event.create!(title: "Clinic night", starts_at: 2.days.ago, points: 3, category: :professional, created_by: officer)
               Attendance.create!(event: event, user: member, recorded_by: officer)
               sign_in_as(member)

               get root_path

               expect(response.body).to include("Clinic night")
               expect(popup).to be_nil
          end

          it "announces only the changes made after the last dismissal" do
               adjust(member, points: "2", category: "general", reason: "First correction.")
               sign_in_as(member)
               get root_path
               dismiss(shown_ids)

               adjust(member, points: "1", category: "social", reason: "Second correction.")
               sign_in_as(member)
               get root_path

               expect(announced_changes.size).to eq(1)
               expect(announced_changes.first).to include("Added 1 social point", "Second correction.")
          end

          it "still announces a change saved while the pop-up was open" do
               adjust(member, points: "2", category: "general", reason: "Shown in the pop-up.")
               sign_in_as(member)
               get root_path
               ids = shown_ids

               adjust(member, points: "1", category: "social", reason: "Saved while the pop-up was open.")
               sign_in_as(member)
               dismiss(ids)
               get root_path

               expect(announced_changes.size).to eq(1)
               expect(announced_changes.first).to include("Saved while the pop-up was open.")
          end

          it "returns to the same page when the pop-up is closed without JavaScript" do
               adjust(member, points: "2", category: "general", reason: "Missed check-in.")
               sign_in_as(member)
               get events_path

               post announcement_dismissal_path, params: { point_adjustment_ids: shown_ids }, headers: { "HTTP_REFERER" => events_url }

               expect(response).to redirect_to(events_url)
               follow_redirect!
               expect(popup).to be_nil
          end
     end

     describe "U12.3: members only see their own record" do
          it "shows each member only their own changes" do
               adjust(member, points: "2", category: "general", reason: "Manny's private reason.")
               adjust(other_member, points: "3", category: "social", reason: "Olga's private reason.")

               sign_in_as(other_member)
               get root_path

               expect(announced_changes).to contain_exactly(a_string_including("Added 3 social points", "Olga's private reason."))
               expect(response.body).not_to include("Manny's private reason.", "Manny Member")
          end

          it "shows no pop-up to a member who has no changes, even when other members do" do
               adjust(member, points: "2", category: "general", reason: "Manny's private reason.")

               sign_in_as(other_member)
               get root_path

               expect(popup).to be_nil
               expect(response.body).not_to include("Manny's private reason.")
          end

          it "does not let a member dismiss another member's announcement" do
               change = adjust(member, points: "2", category: "general", reason: "Manny's private reason.")

               sign_in_as(other_member)
               dismiss([ change.id ])

               expect(change.reload.seen_at).to be_nil
               sign_in_as(member)
               get root_path
               expect(announced_changes.first).to include("Manny's private reason.")
          end

          it "sends visitors to sign in and changes nothing" do
               change = adjust(member, points: "2", category: "general", reason: "Missed check-in.")

               sign_in_as(nil)
               post announcement_dismissal_path, params: { point_adjustment_ids: [ change.id ] }

               expect(response.location).to include("example.com/sign-in")
               expect(change.reload.seen_at).to be_nil
               get root_path
               expect(popup).to be_nil
          end

          it "never shows the pop-up to officers, including a member promoted after a change" do
               adjust(member, points: "2", category: "general", reason: "Missed check-in.")
               member.update!(role: :officer)

               sign_in_as(member.reload)
               get root_path

               expect(popup).to be_nil
          end
     end

     describe "U12.4: closing the pop-up and screen readers" do
          before do
               adjust(member, points: "2", category: "professional", reason: "Attended PTCAS night.")
               sign_in_as(member)
               get root_path
          end

          it "is a dialog named by its heading and described by the list of changes" do
               title = Nokogiri::HTML(response.body).at("##{popup['aria-labelledby']}")
               body = Nokogiri::HTML(response.body).at("##{popup['aria-describedby']}")

               expect(title.text).to eq("Your points were updated")
               expect(body.text.squish).to include("an officer made 1 change to your points", "Added 2 professional points", "Reason: Attended PTCAS night.", "Date:")
          end

          it "has a Close button that gets focus when the pop-up opens" do
               button = popup.at("form button")

               expect(button.text).to eq("Close")
               expect(button["type"]).to eq("submit")
               expect(button).to have_attribute("autofocus")
          end

          it "opens as a modal, and the Close button and the Esc key both record the dismissal" do
               expect(popup["data-controller"]).to eq("announcement")
               # Esc closes a native dialog and fires "close"; the Close button calls close() first.
               expect(popup["data-action"]).to eq("close->announcement#dismiss")
               expect(popup.at("form")["data-action"]).to eq("submit->announcement#close")
               expect(popup.at("form")["action"]).to eq(announcement_dismissal_path)
               expect(popup).to have_attribute("data-turbo-temporary")
          end
     end
end
