require "rails_helper"
require "csv"

RSpec.describe "Non-destructive semester rollover", type: :request do
     include ActiveSupport::Testing::TimeHelpers

  let!(:old_term) { create_term(name: "Synthetic prior term", starts_on: Date.new(2028, 1, 1), ends_on: Date.new(2028, 5, 31)) }
  let!(:new_term) { create_term(name: "Synthetic next term", starts_on: Date.new(2028, 6, 1), ends_on: Date.new(2028, 12, 31)) }
  let!(:member) { create_user(first_name: "Synthetic", last_name: "Member", major: "Synthetic major", tshirt_size: "M") }
  let!(:other_member) { create_user(first_name: "Synthetic", last_name: "Other") }
  let!(:officer) { create_officer(first_name: "Synthetic", last_name: "Officer") }

  def record_event(at:, points: 1, category: :general, attendees: [ member ])
       event = Event.create!(title: "Synthetic #{category} event", starts_at: at, points: points, category: category, created_by: officer)
    attendees.each { |person| Attendance.create!(event: event, user: person, recorded_by: officer) }
    event
  end

  it "starts the new tally at zero at Central midnight and preserves prior totals and profiles" do
       record_event(at: Time.zone.local(2028, 5, 31, 23, 59, 59), points: 5, attendees: [ member, officer ])
    record_event(at: Time.zone.local(2028, 5, 30), category: :professional)
    record_event(at: Time.zone.local(2028, 5, 29), category: :social)
    profiles = User.order(:id).map(&:attributes)
    attendance = Attendance.order(:id).map(&:attributes)
    travel_to Time.zone.local(2028, 5, 31, 23, 59, 59) do
         expect(member.points_earned).to eq(7)
      expect(member).to be_points_requirement_met
    end
    travel_to Time.zone.local(2028, 6, 1) do
         2.times do
              expect(member.points_earned).to eq(0)
           expect(member.points_earned(old_term)).to eq(7)
           expect(member.points_earned(nil)).to eq(7)
           expect(other_member.points_earned).to eq(0)
           expect(officer.points_earned(nil)).to eq(0)
         end
      expect(member.points_by_category).to eq("general" => 0, "professional" => 0, "social" => 0)
      expect(member).not_to be_points_requirement_met
      sign_in_as(member)
      get root_path
      expect(response.body).to include(new_term.name, '<span class="mono">0</span> / 7 points earned')
    end
    expect(User.order(:id).map(&:attributes)).to eq(profiles)
    expect(Attendance.order(:id).map(&:attributes)).to eq(attendance)
  end

  it "assigns UTC timestamps by Central date consistently with the current-term query" do
       # 04:59:59 UTC is still the prior Central day during daylight time.
       before_midnight = Time.utc(2028, 6, 1, 4, 59, 59)
    midnight = Time.utc(2028, 6, 1, 5)
    expect(Term.current(before_midnight)).to eq(old_term)
    expect(old_term.covers?(before_midnight)).to be(true)
    expect(Term.current(midnight)).to eq(new_term)
    expect(new_term.covers?(midnight)).to be(true)
    expect(record_event(at: before_midnight).term).to eq(old_term)
    expect(record_event(at: midnight).term).to eq(new_term)
    expect(member.points_earned(old_term)).to eq(1)
    expect(member.points_earned(new_term)).to eq(1)
  end

  it "handles the daylight-saving jump and repeated hour in the configured zone" do
       [ Time.utc(2028, 3, 12, 7, 59, 59), Time.utc(2028, 3, 12, 8),
         Time.utc(2028, 11, 5, 6, 30), Time.utc(2028, 11, 5, 7, 30) ].each do |timestamp|
            expected = timestamp.month == 3 ? old_term : new_term
         expect(Term.current(timestamp)).to eq(expected)
         expect(record_event(at: timestamp).term).to eq(expected)
       end
  end

  it "reassigns legacy events repeatably without changing attendance or unrelated member fields" do
       event = record_event(at: Time.zone.local(2028, 6, 2))
    event.update_column(:term_id, nil)
    original_attendance = Attendance.order(:id).map(&:attributes)
    original_profile = member.attributes
    2.times { new_term.reassign_events! }
    expect(event.reload.term).to eq(new_term)
    expect(member.points_earned(new_term)).to eq(1)
    expect(Attendance.order(:id).map(&:attributes)).to eq(original_attendance)
    expect(member.reload.attributes).to eq(original_profile)
  end

  it "rolls back term dates and all event assignments after a reassignment failure" do
       event = record_event(at: Time.zone.local(2028, 6, 1))
    allow_any_instance_of(Event).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(event))
    expect { new_term.update!(starts_on: Date.new(2028, 6, 2)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(new_term.reload.starts_on).to eq(Date.new(2028, 6, 1))
    expect(event.reload.term).to eq(new_term)
    expect(member.points_earned(new_term)).to eq(1)
  end

  it "keeps dashboard and member/attendance reports consistent after new accrual" do
       record_event(at: Time.zone.local(2028, 5, 1), points: 5)
    record_event(at: Time.zone.local(2028, 6, 1), points: 2, category: :professional, attendees: [ member, officer ])
    travel_to Time.zone.local(2028, 6, 2) do
         expect(member.points_earned).to eq(2)
      expect(member.points_by_category).to include("professional" => 2, "general" => 0)
      rows = CSV.parse(OfficerCsvExport.new(report: "members", term: new_term).generate, headers: true)
      expect(rows.find { |row| row["User ID"] == member.id.to_s }["Points"]).to eq("2")
      expect(rows.find { |row| row["User ID"] == other_member.id.to_s }["Points"]).to eq("0")
      expect(rows.map { |row| row["User ID"] }).not_to include(officer.id.to_s)
      history = CSV.parse(OfficerCsvExport.new(report: "members", term: old_term).generate, headers: true)
      expect(history.find { |row| row["User ID"] == member.id.to_s }["Points"]).to eq("5")
      attendance = CSV.parse(OfficerCsvExport.new(report: "attendances", term: new_term).generate, headers: true)
      expect(attendance.find { |row| row["User ID"] == officer.id.to_s }["Points"]).to eq("0")
      sign_in_as(member)
      get root_path
      expect(response.body).to include('<span class="mono">2</span> / 7 points earned')
    end
  end

  it "rejects overlapping term dates, including a shared boundary day" do
       expect { old_term.update!(ends_on: new_term.starts_on) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(old_term.reload.ends_on).to eq(Date.new(2028, 5, 31))
  end

  it "preserves old adjustments and scopes new corrections to the current term only" do
       old_adjustment = PointAdjustment.create!(user: member, term: old_term, recorded_by: officer,
         points: 3, category: :professional, reason: "Prior semester correction")
       original = old_adjustment.attributes
       travel_to Time.zone.local(2028, 6, 1) do
            sign_in_as(officer)
            expect(member.points_earned).to eq(0)
            post officer_member_point_adjustments_path(member), params: {
              point_adjustment: { points: 2, category: "social", reason: "Current correction", term_id: old_term.id }
            }
            expect(response).to redirect_to(officer_member_path(member))
            expect(PointAdjustment.last.term).to eq(new_term)
            expect(member.points_earned).to eq(2)
            expect(member.points_history(new_term)).to contain_exactly(PointAdjustment.last)
            expect(member.points_history(old_term)).to contain_exactly(old_adjustment)
            expect(old_adjustment.reload.attributes).to eq(original)

            expect {
                 post officer_member_point_adjustments_path(officer), params: {
                   point_adjustment: { points: 1, category: "general", reason: "Officer attempt" }
                 }
            }.not_to change(PointAdjustment, :count)
            expect(response).to have_http_status(:unprocessable_entity)
       end
  end

  it "rejects a form left open across the boundary without moving its adjustment to the new term" do
       sign_in_as(officer)
       travel_to Time.zone.local(2028, 5, 31, 23, 59) do
            get officer_member_path(member)
            form = Nokogiri::HTML(response.body)
            expect(form.at_css("input[name='expected_term_id']")["value"]).to eq(old_term.id.to_s)
       end
       travel_to Time.zone.local(2028, 6, 1) do
            expect {
                 post officer_member_point_adjustments_path(member), params: {
                   expected_term_id: old_term.id,
                   point_adjustment: { points: 2, category: "general", reason: "Stale form" }
                 }
            }.not_to change(PointAdjustment, :count)
            expect(response).to redirect_to(officer_member_path(member))
            expect(flash[:alert]).to include("current semester changed")
            expect(member.points_earned).to eq(0)
       end
  end

  it "lets officers download separately labeled prior and current semester history after rollover" do
       record_event(at: Time.zone.local(2028, 5, 1), points: 5)
       travel_to Time.zone.local(2028, 6, 2) do
            sign_in_as(officer)
            [ [ old_term, "5" ], [ new_term, "0" ] ].each do |term, expected|
                 get export_officer_csv_transfer_path, params: { report: "members", term_id: term.id }
                 expect(response).to have_http_status(:ok)
                 row = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true).find { |item| item["User ID"] == member.id.to_s }
                 expect(row["Period"]).to eq(term.name)
                 expect(row["Points"]).to eq(expected)
            end
            get export_officer_csv_transfer_path, params: { report: "attendances", term_id: old_term.id }
            row = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true).first
            expect(row["Term"]).to eq(old_term.name)
            expect(row["Points"]).to eq("5")
       end
  end

  it "shows prior adjustment reasons without changing which semester the correction form applies to" do
       prior_checkin = record_event(at: Time.zone.local(2028, 5, 1), points: 5)
       prior_checkin.update!(title: "Prior check-in")
       PointAdjustment.create!(user: member, term: old_term, recorded_by: officer,
         points: 2, category: :general, reason: "Prior check-in correction")
       PointAdjustment.create!(user: member, term: new_term, recorded_by: officer,
         points: 1, category: :social, reason: "Current check-in correction")
       travel_to Time.zone.local(2028, 6, 2) do
            sign_in_as(officer)
            get officer_member_path(member), params: { history_term_id: old_term.id }
            expect(response).to have_http_status(:ok)
            page = Nokogiri::HTML(response.body)
            expect(page.css("h2").map(&:text)).to include("Points history · #{old_term.name}")
            expect(page.at_css("ol.points-history").text).to include("Prior check-in", "Prior check-in correction")
            expect(page.at_css("ol.points-history").text).not_to include("Current check-in correction")
            expect(page.at_css("input[name='expected_term_id']")["value"]).to eq(new_term.id.to_s)

            get officer_member_path(member), params: { history_term_id: "all" }
            expect(Nokogiri::HTML(response.body).at_css("ol.points-history").text).to include("Prior check-in correction", "Current check-in correction")
            get officer_member_path(member), params: { history_term_id: "nonexistent" }
            expect(response).to have_http_status(:not_found)
       end
  end
end
