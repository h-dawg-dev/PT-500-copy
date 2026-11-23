require "rails_helper"

RSpec.describe "Protecting points when credit changes", type: :request do
     let!(:term) { create_current_term }
     let(:officer) { create_officer }
     let(:member) { create_user }
     let!(:event) { Event.create!(title: "Workshop", starts_at: 1.hour.from_now, points: 3, created_by: officer) }
     let!(:attendance) { Attendance.create!(event: event, user: member, recorded_by: officer) }
     let!(:deduction) { PointAdjustment.create!(user: member, term: term, recorded_by: officer, points: -2, category: :general, reason: "Correction") }

     before { sign_in_as(officer) }

     it "rejects a points reduction that would make a category negative and explains how to correct it" do
          patch officer_event_path(event), params: { event: { points: 0, title: "Changed" } }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include("below zero", "Reverse or offset deductions")
          expect(event.reload.points).to eq(3)
          expect(event.title).to eq("Workshop")
          expect(member.points_earned(term)).to eq(1)
     end

     it "allows reductions that leave exactly zero" do
          patch officer_event_path(event), params: { event: { points: 2 } }

          expect(response).to redirect_to(officer_event_path(event))
          expect(event.reload.points).to eq(2)
          expect(member.points_earned(term)).to eq(0)
     end

     it "rejects moving credit into another category" do
          patch officer_event_path(event), params: { event: { category: "social" } }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(event.reload).to be_general
          expect(member.points_by_category(term)["general"]).to eq(1)
     end

     it "rejects moving credit into a different term" do
          other = create_term(name: "Next term", starts_on: term.ends_on + 1.day, ends_on: term.ends_on + 30.days)

          patch officer_event_path(event), params: { event: { starts_at: other.starts_on.in_time_zone + 12.hours } }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(event.reload.term).to eq(term)
     end

     it "rejects moving credit outside every term" do
          patch officer_event_path(event), params: { event: { starts_at: term.ends_on + 2.years } }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(event.reload.term).to eq(term)
     end

     it "rejects event deletion before deleting any attendance or RSVPs" do
          another = Attendance.create!(event: event, user: create_user, recorded_by: officer)
          rsvp = Rsvp.create!(event: event, user: member)

          expect { delete officer_event_path(event) }.not_to change(Event, :count)

          expect(response).to redirect_to(officer_event_path(event))
          follow_redirect!
          expect(response.body).to include("below zero")
          expect(event.attendances.reload).to contain_exactly(attendance, another)
          expect(event.rsvps.reload).to include(rsvp)
          expect(deduction.reload.points).to eq(-2)
     end

     it "rejects attendance removal as JSON without changing stored credit" do
          expect { delete officer_event_attendance_path(event, attendance), as: :json }.not_to change(Attendance, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body["error"]).to include("below zero", "Reverse or offset deductions")
          expect(member.points_earned(term)).to eq(1)
     end

     it "explains rejected attendance removal to an HTML client" do
          delete officer_event_attendance_path(event, attendance)

          expect(response).to redirect_to(officer_event_path(event))
          follow_redirect!
          expect(response.body).to include("below zero")
          expect(Attendance.exists?(attendance.id)).to be(true)
     end

     it "allows credit removal after an explicit offset, preserving the adjustment history" do
          offset = PointAdjustment.create!(user: member, term: term, recorded_by: officer, points: 2, category: :general, reason: "Reverse deduction before attendance correction")

          delete officer_event_attendance_path(event, attendance), as: :json

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["present"]).to be(false)
          expect(member.points_earned(term)).to eq(0)
          expect(member.point_adjustments).to contain_exactly(deduction, offset)
     end

     it "allows unrelated event edits without changing points" do
          patch officer_event_path(event), params: { event: { title: "Updated workshop", location: "Room 1" } }

          expect(response).to redirect_to(officer_event_path(event))
          expect(event.reload.title).to eq("Updated workshop")
          expect(member.points_earned(term)).to eq(1)
     end

     it "allows event deletion after an offset without deleting adjustment history" do
          offset = PointAdjustment.create!(user: member, term: term, recorded_by: officer, points: 2, category: :general, reason: "Reverse deduction before event correction")

          delete officer_event_path(event)

          expect(response).to redirect_to(officer_events_path)
          expect(Event.exists?(event.id)).to be(false)
          expect(Attendance.exists?(attendance.id)).to be(false)
          expect(member.points_earned(term)).to eq(0)
          expect(member.point_adjustments).to contain_exactly(deduction, offset)
     end

     it "rolls back a term date edit if its event reassignment would remove required credit" do
          previous_end = term.ends_on

          expect { term.update!(ends_on: Date.yesterday) }.to raise_error(ActiveRecord::RecordInvalid, /below zero/)

          expect(term.reload.ends_on).to eq(previous_end)
          expect(event.reload.term).to eq(term)
          expect(member.points_earned(term)).to eq(1)
     end

     it "keeps officer attendance outside the points system" do
          member.update!(role: :officer)

          delete officer_event_path(event)

          expect(response).to redirect_to(officer_events_path)
          expect(Event.exists?(event.id)).to be(false)
          expect(Attendance.exists?(attendance.id)).to be(false)
     end

     it "also protects direct model mutations" do
          expect(event.update(points: 0)).to be(false)
          expect(attendance.destroy).to be(false)
          expect(event.destroy).to be(false)
          expect(member.points_earned(term)).to eq(1)
     end

     it "can delete an entire member ledger without blocking on its own deductions" do
          expect { member.destroy! }.not_to raise_error

          expect(Attendance.exists?(attendance.id)).to be(false)
          expect(PointAdjustment.exists?(deduction.id)).to be(false)
     end
end
