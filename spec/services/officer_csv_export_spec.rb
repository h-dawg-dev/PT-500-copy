require "rails_helper"
require "csv"

RSpec.describe OfficerCsvExport do
     include ActiveSupport::Testing::TimeHelpers
     before { travel_to Time.zone.local(2026, 9, 1) }
     after { travel_back }
     let(:officer) { create_officer }
     let(:member) { create_user(first_name: "=SUM(1,2)") }
     let(:term) { create_term(required_points: 3) }

     def report(name, period = term)
          CSV.parse(described_class.new(report: name, term: period).generate, headers: true)
     end

     def event(category, points, starts_at: Time.zone.local(2026, 9, 22, 19), **attributes)
          Event.create!({ title: "Workshop, practice", starts_at: starts_at, category: category, points: points, created_by: officer }.merge(attributes))
     end

     it "exports attendance-based totals matching the existing points rules, including zero-attendance members" do
          term
          quiet_member = create_user
          [ :general, :professional, :social ].each do |category|
               Attendance.create!(event: event(category, 1), user: member, recorded_by: officer)
          end
          Rsvp.create!(event: event(:general, 20), user: member)
          Attendance.create!(event: event(:general, 9, starts_at: Time.zone.local(2027, 1, 1)), user: member)
          row = report("members").find { |item| item["User ID"] == member.id.to_s }
          expect(row.values_at("Attendance Count", "Points", "General Points", "Professional Points", "Social Points", "Requirement Met")).to eq(%w[3 3 1 1 1 true])
          expect(row["Points"].to_i).to eq(member.points_earned(term))
          expect(row["Name"]).to start_with("'=")
          zero = report("members").find { |item| item["User ID"] == quiet_member.id.to_s }
          expect(zero.values_at("Points", "Requirement Met")).to eq(%w[0 false])
          expect(report("members").map { |item| item["User ID"] }).not_to include(officer.id.to_s)
          all = report("members", nil).find { |item| item["User ID"] == member.id.to_s }
          expect(all.values_at("Points", "Period", "Required Points")).to eq([ "12", "All time", "7" ])
     end

     # O14.1, O14.4
     it "adds point adjustments to member totals and shows them in their own column" do
          Attendance.create!(event: event(:social, 1), user: member, recorded_by: officer)
          PointAdjustment.create!(user: member, term: term, recorded_by: officer, points: 2, category: :professional, reason: "Missed check-in")
          spring = create_term(name: "Spring adjustments", starts_on: Date.new(2027, 1, 10), ends_on: Date.new(2027, 5, 1))
          PointAdjustment.create!(user: member, term: spring, recorded_by: officer, points: 4, category: :general, reason: "Missed check-in")
          row = report("members").find { |item| item["User ID"] == member.id.to_s }
          expect(row.values_at("Attendance Count", "Adjustment Points", "Points", "Professional Points", "Requirement Met")).to eq(%w[1 2 3 2 true])
          all = report("members", nil).find { |item| item["User ID"] == member.id.to_s }
          expect(all.values_at("Adjustment Points", "Points", "General Points")).to eq(%w[6 7 4])
     end

     it "exports event details and counts for the selected period and quotes spreadsheet formulas safely" do
          term
          session = event(:social, 2, title: "  =HYPERLINK(\"x\")", notes: "line one\nline two, café", getinvolved_reference: "EVN-1", getinvolved_data: { "Status" => "Approved" })
          Attendance.create!(event: session, user: member)
          Rsvp.create!(event: session, user: officer)
          event(:general, 1, starts_at: Time.zone.local(2027, 1, 1))
          rows = report("events")
          expect(rows.size).to eq(1)
          expect(rows.first.values_at("Title", "Notes", "Starts", "Attendance Count", "RSVP Count", "GetInvolved Status")).to eq([
            "'  =HYPERLINK(\"x\")", "line one\nline two, café", "2026-09-22T19:00:00-05:00", "1", "1", "Approved"
          ])
          expect(report("events", nil).size).to eq(2)
     end

     it "exports actual attendance with recorder and member details, excluding RSVPs" do
          term
          session = event(:professional, 2)
          Attendance.create!(event: session, user: member, recorded_by: officer)
          Rsvp.create!(event: session, user: officer)
          Attendance.create!(event: event(:general, 1, starts_at: Time.zone.local(2027, 1, 1)), user: officer)
          rows = report("attendances")
          expect(rows.size).to eq(1)
          expect(rows.first.values_at("Event ID", "Email", "Recorded By", "Points")).to eq([ session.id.to_s, member.email, officer.display_name, "2" ])
          expect(report("attendances", nil).size).to eq(2)
     end

     it "keeps officer attendance in the attendance report at zero points and out of the members report" do
          term
          session = event(:social, 4)
          Attendance.create!(event: session, user: officer, recorded_by: officer)
          Attendance.create!(event: session, user: member, recorded_by: officer)
          rows = report("attendances").to_h { |row| [ row["Email"], row.values_at("Role", "Points") ] }
          expect(rows).to eq(officer.email => %w[officer 0], member.email => %w[member 4])
          expect(report("members").map { |row| row.values_at("Email", "Points") }).to eq([ [ member.email, "4" ] ])
     end

     it "exports header-only CSVs for empty event and attendance reports" do
          expect(report("events")).to be_empty
          expect(report("events").headers).to include("GetInvolved Reference")
          expect(report("attendances")).to be_empty
     end
end
