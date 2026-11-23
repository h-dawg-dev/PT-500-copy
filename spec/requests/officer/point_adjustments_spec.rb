require "rails_helper"
require "csv"

RSpec.describe "Officers adjusting a member's points", type: :request do
     let!(:term) { create_current_term }
     let(:officer) { create_officer(first_name: "Dana", last_name: "Desk") }
     let(:member) { create_user(first_name: "Manny", last_name: "Member") }
     let(:other_member) { create_user(first_name: "Olga", last_name: "Other") }

     def adjust(person, fields)
          post officer_member_point_adjustments_path(person), params: { point_adjustment: fields }
     end

     def page
          Nokogiri::HTML(response.body)
     end

     def facts
          page.css("section.points-summary dl.facts > div").to_h { |fact| [ fact.at("dt").text, fact.at("dd").text.squish ] }
     end

     def history
          page.css("ol.points-history li").map { |entry| entry.text.squish }
     end

     def attend(person, points:, category: :general, starts_at: 2.days.ago)
          event = Event.create!(title: "#{category.to_s.humanize} session", starts_at: starts_at, points: points, category: category, created_by: officer)
          Attendance.create!(event: event, user: person, recorded_by: officer)
     end

     before { sign_in_as(officer) }

     describe "O14.1: finding a member's record" do
          it "links to member records from the officer dashboard" do
               get officer_root_path

               expect(page.at("a[href='#{officer_members_path}']").text).to eq("Member records and point adjustments")
          end

          it "lists everyone with a link to their record and this term's points" do
               attend(member, points: 3)
               other_member

               get officer_members_path

               expect(response).to have_http_status(:ok)
               rows = page.css("table.roster tbody tr").to_h { |row| [ row.at("td").text, row.css("td").map { |cell| cell.text.squish } ] }
               expect(rows["Manny Member"]).to eq([ "Manny Member", member.email, "member", "3 / 7" ])
               expect(rows["Olga Other"].last).to eq("0 / 7")
               expect(rows["Dana Desk"]).to eq([ "Dana Desk", officer.email, "officer no points", "—" ])
               expect(page.at("a[href='#{officer_member_path(member)}']").text).to eq("Manny Member")
          end
     end

     describe "O14.1: adding or subtracting points from a member's record" do
          it "shows the member's points and the adjustment form" do
               attend(member, points: 2, category: :professional)

               get officer_member_path(member)

               expect(response).to have_http_status(:ok)
               expect(page.at("h1").text).to eq("Manny Member")
               expect(page.at("p.tape-tab").text.squish).to eq("2 / 7 points earned")
               expect(facts).to eq("General" => "0", "Professional" => "2 / 1 needed", "Social" => "0 / 1 needed")
               form = page.at("form[action='#{officer_member_point_adjustments_path(member)}']")
               expect(form.css("[name^='point_adjustment[']").map { |field| field["name"] }).to contain_exactly(
                    "point_adjustment[points]", "point_adjustment[category]", "point_adjustment[reason]"
               )
               expect(form.css("select option").map(&:text)).to eq([ "Choose a category", "General", "Professional", "Social" ])
          end

          it "adds points in the chosen category and updates the total, category progress and history right away" do
               attend(member, points: 2, category: :professional)

               expect {
                    adjust(member, points: "3", category: "social", reason: "Volunteered at the 5K but was not checked in.")
               }.to change(PointAdjustment, :count).by(1)

               expect(response).to redirect_to(officer_member_path(member))
               follow_redirect!
               expect(page.at("p.notice").text).to eq("Added 3 social points to Manny Member's #{term.name} total.")
               expect(page.at("p.tape-tab").text.squish).to eq("5 / 7 points earned")
               expect(facts).to include("Social" => "3 / 1 needed")
               expect(response.body).to include("2 more points needed in total")
               expect(response.body).not_to include("social point still needed")
               expect(history.first).to include("Point adjustment · Social", "Volunteered at the 5K but was not checked in.", "by Dana Desk", "+3")
               expect(history.last).to include("Professional session", "+2")

               adjustment = PointAdjustment.last
               expect(adjustment).to have_attributes(user: member, term: term, recorded_by: officer, points: 3, category: "social")
          end

          it "subtracts points with a negative amount" do
               attend(member, points: 4, category: :general)

               adjust(member, points: "-1", category: "general", reason: "Left the meeting early.")

               expect(response).to redirect_to(officer_member_path(member))
               follow_redirect!
               expect(page.at("p.notice").text).to eq("Subtracted 1 general point from Manny Member's #{term.name} total.")
               expect(page.at("p.tape-tab").text.squish).to eq("3 / 7 points earned")
               expect(history.first).to include("Point adjustment · General", "Left the meeting early.", "-1")
          end

          it "shows the change on the member's own home page and history" do
               adjust(member, points: "2", category: "professional", reason: "Attended PTCAS night; sign-in sheet was lost.")
               sign_in_as(member)

               get root_path

               expect(response.body).to match(%r{<span class="mono">2</span> / 7 points earned})
               expect(response.body).to include("5 more points needed in total", "1 social point still needed")
               expect(response.body).not_to include("professional point still needed")
               expect(page.css("h2").map(&:text)).to include("Your points history")
               expect(history).to contain_exactly(a_string_including("Point adjustment · Professional", "Attended PTCAS night; sign-in sheet was lost.", "+2"))
          end

          it "counts adjustments toward meeting the requirement" do
               attend(member, points: 5, category: :professional)
               attend(member, points: 1, category: :social)

               adjust(member, points: "1", category: "general", reason: "Missed check-in at the general meeting.")
               sign_in_as(member)
               get root_path

               expect(response.body).to include("You have met the points requirement.")
          end

          it "includes adjustments in the members and points report" do
               attend(member, points: 2, category: :professional)
               adjust(member, points: "3", category: "social", reason: "Missed check-in.")

               get export_officer_csv_transfer_path, params: { report: "members", term_id: term.id }

               row = CSV.parse(response.body.delete_prefix("﻿"), headers: true).find { |item| item["User ID"] == member.id.to_s }
               expect(row.to_h).to include("Attendance Count" => "1", "Adjustment Points" => "3", "Points" => "5", "Social Points" => "3", "Professional Points" => "2")
          end
     end

     describe "O14.2: invalid adjustments" do
          def expect_nothing_saved_with(fields, message)
               expect { adjust(member, fields) }.not_to change(PointAdjustment, :count)

               expect(response).to have_http_status(:unprocessable_entity)
               alert = page.at("#adjust-points .alert")
               expect(alert.text).to include("Could not save the adjustment. Nothing was changed.", message)
          end

          let(:valid) { { points: "2", category: "general", reason: "Missed check-in." } }

          it "rejects a blank amount" do
               expect_nothing_saved_with(valid.merge(points: ""), "Amount is required. Enter a whole number of points, such as 2 or -2")
          end

          it "rejects an amount that is not a whole number" do
               expect_nothing_saved_with(valid.merge(points: "2.5"), "Amount must be a whole number, such as 2 or -2")
               expect_nothing_saved_with(valid.merge(points: "two"), "Amount must be a whole number, such as 2 or -2")
          end

          it "rejects zero" do
               expect_nothing_saved_with(valid.merge(points: "0"), "Amount can't be zero")
          end

          it "rejects a missing category" do
               expect_nothing_saved_with(valid.merge(category: ""), "Category is required. Choose general, professional, or social")
          end

          it "rejects a category that is not offered" do
               expect_nothing_saved_with(valid.merge(category: "bogus"), "Category is not included in the list")
          end

          it "rejects a blank reason" do
               expect_nothing_saved_with(valid.merge(reason: "  "), "Reason is required. Say why the points are changing")
          end

          it "will not take a category below zero" do
               attend(member, points: 1, category: :social)

               expect_nothing_saved_with(valid.merge(points: "-2", category: "social"),
                    "Manny Member has only 1 social point in #{term.name}, so you can subtract at most 1.")
               expect(member.points_earned).to eq(1)
          end

          it "lists every problem at once and keeps what the officer typed" do
               adjust(member, points: "2.5", category: "", reason: "Missed check-in.")

               messages = page.css("#adjust-points .alert li").map(&:text)
               expect(messages).to contain_exactly("Amount must be a whole number, such as 2 or -2", "Category is required. Choose general, professional, or social")
               expect(page.at("input[name='point_adjustment[points]']")["value"]).to eq("2.5")
               expect(page.at("textarea[name='point_adjustment[reason]']").text.strip).to eq("Missed check-in.")
               expect(page.at("p.tape-tab").text.squish).to eq("0 / 7 points earned")
          end
     end

     describe "O14.3: who can adjust and who can be adjusted" do
          it "sends members away from member records and the adjustment form" do
               sign_in_as(member)

               [ officer_members_path, officer_member_path(member), officer_member_path(other_member) ].each do |path|
                    get path

                    expect(response).to redirect_to(root_path)
                    expect(flash[:alert]).to eq("That area is for officers.")
               end
          end

          it "does not save an adjustment a member submits, even for themselves" do
               sign_in_as(member)

               expect {
                    adjust(member, points: "5", category: "general", reason: "I deserve it.")
               }.not_to change(PointAdjustment, :count)

               expect(response).to redirect_to(root_path)
               expect(member.points_earned).to eq(0)
          end

          it "sends visitors to sign in and saves nothing" do
               sign_in_as(nil)

               expect { adjust(member, points: "5", category: "general", reason: "Anonymous.") }.not_to change(PointAdjustment, :count)

               expect(response.location).to include("example.com/sign-in")
               get officer_member_path(member)
               expect(response.location).to include("example.com/sign-in")
          end

          it "shows no adjustment form on an officer's record" do
               other_officer = create_officer(first_name: "Olive", last_name: "Officer")

               get officer_member_path(other_officer)

               expect(response).to have_http_status(:ok)
               expect(page.at("form[action='#{officer_member_point_adjustments_path(other_officer)}']")).to be_nil
               expect(page.at("#adjust-points").text).to include("Officers are not part of the points system, so they can't be given points.")
          end

          it "refuses to give an officer points, including the officer making the change" do
               other_officer = create_officer(first_name: "Olive", last_name: "Officer")

               [ other_officer, officer ].each do |person|
                    expect { adjust(person, points: "2", category: "general", reason: "Ran the meeting.") }.not_to change(PointAdjustment, :count)

                    expect(response).to have_http_status(:unprocessable_entity)
                    expect(page.at("#adjust-points .alert").text).to include("Officers are not part of the points system, so they can't be given points.")
                    expect(person.points_earned).to eq(0)
               end
          end
     end

     describe "O14.4: what an adjustment changes" do
          it "changes only the selected member" do
               attend(other_member, points: 2)

               adjust(member, points: "3", category: "general", reason: "Missed check-in.")

               expect(member.points_earned).to eq(3)
               expect(other_member.points_earned).to eq(2)
               get officer_member_path(other_member)
               expect(history.join).not_to include("Point adjustment")
          end

          it "changes only the current semester" do
               past = create_term(name: "Past term", starts_on: term.starts_on - 200.days, ends_on: term.starts_on - 100.days)
               attend(member, points: 4, starts_at: (past.starts_on + 10.days).in_time_zone)

               adjust(member, points: "3", category: "general", reason: "Missed check-in.")

               expect(PointAdjustment.last.term).to eq(term)
               expect(member.points_earned(term)).to eq(3)
               expect(member.points_earned(past)).to eq(4)
               expect(member.points_earned(nil)).to eq(7)
          end

          it "keeps the adjustment after a refresh and after signing out and back in" do
               adjust(member, points: "2", category: "social", reason: "Missed check-in.")

               2.times do
                    get officer_member_path(member)
                    expect(page.at("p.tape-tab").text.squish).to eq("2 / 7 points earned")
               end

               sign_in_as(nil)
               get root_path
               expect(response.body).not_to include("points earned")

               sign_in_as(User.find(member.id))
               get root_path
               expect(response.body).to match(%r{<span class="mono">2</span> / 7 points earned})
               expect(history.first).to include("Point adjustment · Social", "+2")
          end
     end

     describe "O14.4: without a current term" do
          include ActiveSupport::Testing::TimeHelpers

          it "explains that there is no semester to adjust and saves nothing" do
               travel_to(term.ends_on + 30.days) do
                    get officer_member_path(member)
                    expect(page.at("form[action='#{officer_member_point_adjustments_path(member)}']")).to be_nil
                    expect(page.at("#adjust-points").text).to include("No term covers today")

                    expect { adjust(member, points: "2", category: "general", reason: "Missed check-in.") }.not_to change(PointAdjustment, :count)
                    expect(response).to have_http_status(:unprocessable_entity)
                    expect(page.at("#adjust-points .alert").text).to include("No term covers today, so there is no current semester to adjust.")
               end
          end
     end
end
