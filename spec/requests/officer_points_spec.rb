require "rails_helper"
require "csv"

RSpec.describe "Officers and the points system", type: :request do
  let(:desk_officer) { create_officer(first_name: "Dana", last_name: "Desk") }
  let(:officer) { create_officer(first_name: "Olive", last_name: "Officer") }
  let(:member) { create_user(first_name: "Manny", last_name: "Member") }
  let(:event) { Event.create!(title: "Clinic night", starts_at: 2.days.ago, points: 3, category: :professional, created_by: desk_officer) }

  def check_in(person)
    post officer_event_attendances_path(event), params: { user_id: person.id }, as: :json
    JSON.parse(response.body)
  end

  def report(name, term_id: "all")
    get export_officer_csv_transfer_path, params: { report: name, term_id: term_id }
    CSV.parse(response.body.delete_prefix("﻿"), headers: true)
  end

  def row_for(rows, person)
    rows.find { |row| row["User ID"] == person.id.to_s }
  end

  before { sign_in_as(desk_officer) }

  describe "checking in" do
    it "saves an officer's attendance and awards zero points" do
      payload = nil
      expect { payload = check_in(officer) }.to change(Attendance, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(payload).to include("present" => true, "points_awarded" => 0, "present_count" => 1)
      expect(Attendance.find_by!(event: event, user: officer).recorded_by).to eq(desk_officer)
      expect(officer.points_earned(nil)).to eq(0)
    end

    it "lets an officer check themselves in for zero points too" do
      payload = check_in(desk_officer)

      expect(payload).to include("present" => true, "points_awarded" => 0)
      expect(desk_officer.points_earned(nil)).to eq(0)
    end

    it "still gives a member the session's points for the same event" do
      check_in(officer)
      payload = check_in(member)

      expect(payload).to include("present" => true, "points_awarded" => 3, "present_count" => 2)
      expect(member.points_earned(nil)).to eq(3)
      expect(member.points_by_category(nil)).to include("professional" => 3)
    end
  end

  describe "attendance records" do
    before do
      check_in(officer)
      check_in(member)
    end

    it "keeps the officer on the roster as present, marked as earning no points" do
      get officer_event_path(event)

      roster = Nokogiri::HTML(response.body)
      officer_row = roster.at("tr.roster-row[data-user-id='#{officer.id}']")
      member_row = roster.at("tr.roster-row[data-user-id='#{member.id}']")
      expect(officer_row["data-present"]).to eq("true")
      expect(officer_row.text).to include("Present", "no points")
      expect(member_row["data-present"]).to eq("true")
      expect(member_row.text).not_to include("no points")
      expect(roster.at("[data-roster-target='presentCount']").text).to eq("2")
    end

    it "lists the officer in the attendance report with zero points" do
      rows = report("attendances")

      expect(rows.size).to eq(2)
      expect(row_for(rows, officer).to_h).to include("Event" => "Clinic night", "Role" => "officer", "Points" => "0")
      expect(row_for(rows, member).to_h).to include("Event" => "Clinic night", "Role" => "member", "Points" => "3")
    end

    it "counts the officer in the session's attendance count" do
      expect(report("events").first["Attendance Count"]).to eq("2")
    end

    it "shows the officer their own check-in without implying points" do
      sign_in_as(officer)

      get event_path(event)

      expect(response.body).to include("Marked present")
      expect(response.body).to include("no points for officers")
    end

    it "does not add the note for members" do
      sign_in_as(member)

      get event_path(event)

      expect(response.body).to include("Marked present")
      expect(response.body).not_to include("no points for officers")
    end
  end

  describe "points report" do
    before do
      create_current_term
      check_in(officer)
      check_in(member)
    end

    it "leaves officers out and keeps members, including those who never attended" do
      quiet_member = create_user(first_name: "Quinn", last_name: "Quiet")

      rows = report("members")

      expect(rows.map { |row| row["User ID"] }).to contain_exactly(member.id.to_s, quiet_member.id.to_s)
      expect(rows.map { |row| row["Role"] }.uniq).to eq([ "member" ])
      expect(row_for(rows, member).to_h).to include("Attendance Count" => "1", "Points" => "3", "Professional Points" => "3")
      expect(row_for(rows, quiet_member).to_h).to include("Attendance Count" => "0", "Points" => "0")
    end

    it "does not show an officer a points total on their home page" do
      sign_in_as(officer)

      get root_path

      expect(response.body).to include("Officers are not part of the points system")
      expect(response.body).not_to include("pts on your own chart")
      expect(response.body).not_to include("points earned")
    end

    it "still shows a member their points on their home page" do
      sign_in_as(member)

      get root_path

      expect(response.body).to include("Clinic night")
      expect(response.body).to match(%r{<span class="mono">3</span> / 7 points earned})
    end
  end

  describe "regenerating reports" do
    before do
      check_in(officer)
      check_in(member)
    end

    it "gives officers nothing however many times the reports are run" do
      3.times do
        expect(row_for(report("members"), officer)).to be_nil
        expect(row_for(report("attendances"), officer)["Points"]).to eq("0")
        expect(row_for(report("members"), member)["Points"]).to eq("3")
      end

      expect(officer.reload.points_earned(nil)).to eq(0)
    end

    it "gives officers nothing in a term report either" do
      term = create_term(name: "Report term", starts_on: Date.current - 30.days, ends_on: Date.current + 30.days)
      event.update!(starts_at: 2.days.ago)

      expect(event.reload.term).to eq(term)
      expect(row_for(report("members", term_id: term.id), officer)).to be_nil
      expect(row_for(report("attendances", term_id: term.id), officer)["Points"]).to eq("0")
      expect(row_for(report("members", term_id: term.id), member)["Points"]).to eq("3")
    end

    it "follows a change to the session's points for members only" do
      event.update!(points: 5)

      expect(row_for(report("attendances"), officer)["Points"]).to eq("0")
      expect(row_for(report("attendances"), member)["Points"]).to eq("5")
      expect(row_for(report("members"), member)["Points"]).to eq("5")
      expect(officer.reload.points_earned(nil)).to eq(0)
    end

    it "drops a member's points once they become an officer, keeping the attendance" do
      member.update!(role: :officer)

      expect(row_for(report("members"), member)).to be_nil
      expect(row_for(report("attendances"), member).to_h).to include("Role" => "officer", "Points" => "0")
      expect(member.points_earned(nil)).to eq(0)
    end
  end
end
