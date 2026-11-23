require "rails_helper"

RSpec.describe "Term accounting and session review regressions", type: :model do
     include ActiveSupport::Testing::TimeHelpers
     def session_at(time, **attrs)
          Event.create!({ title: "Review session", starts_at: time, points: 2 }.merge(attrs))
     end

     it "does not treat old credit as a current semester when no term covers today" do
          travel_to Time.zone.local(2100, 7, 1) do
               term = create_term(starts_on: Date.new(2100, 1, 1), ends_on: Date.new(2100, 5, 1))
               member = create_user
               %i[general professional social].each do |category|
                    event = session_at(Time.zone.local(2100, 3, 1), points: category == :general ? 5 : 1, category: category)
                    Attendance.create!(event: event, user: member)
               end
               expect(Term.current).to be_nil
               expect(member.points_earned).to eq(0)
               expect(member.points_by_category.values).to all(eq(0))
               expect(member.points_requirement_met?).to be(false)
               expect(member.points_earned(term)).to eq(7)
               expect(member.points_earned(nil)).to eq(7)
          end
     end

     it "keeps existing attendance and includes its points when the term is created later" do
          member = create_user
          event = session_at(Time.zone.local(2090, 9, 1))
          attendance = Attendance.create!(event: event, user: member)
          expect(event.term).to be_nil
          term = create_term(starts_on: Date.new(2090, 8, 1), ends_on: Date.new(2090, 12, 1))
          expect(event.reload.term).to eq(term)
          expect(Attendance.find(attendance.id)).to have_attributes(event_id: event.id, user_id: member.id)
          expect(member.points_earned(term)).to eq(2)
     end

     it "reassigns events when term dates shrink or expand" do
          term = create_term(starts_on: Date.new(2090, 8, 1), ends_on: Date.new(2090, 12, 1))
          inside = session_at(Time.zone.local(2090, 8, 15))
          outside = session_at(Time.zone.local(2090, 12, 15))
          term.update!(starts_on: Date.new(2090, 9, 1), ends_on: Date.new(2090, 12, 31))
          expect(inside.reload.term).to be_nil
          expect(outside.reload.term).to eq(term)
     end

     it "uses Central calendar dates at the start and end boundaries" do
          first = session_at(Time.zone.local(2090, 9, 1, 0, 0))
          last = session_at(Time.zone.local(2090, 9, 30, 23, 59))
          next_day = session_at(Time.zone.local(2090, 10, 1, 0, 0))
          term = create_term(starts_on: Date.new(2090, 9, 1), ends_on: Date.new(2090, 9, 30))
          expect(first.reload.term).to eq(term)
          expect(last.reload.term).to eq(term)
          expect(next_day.reload.term).to be_nil
     end

     it "rejects overlaps including shared boundary days, while permitting adjacent terms" do
          first = create_term(starts_on: Date.new(2090, 1, 1), ends_on: Date.new(2090, 5, 1))
          overlap = Term.new(name: "Overlap", starts_on: Date.new(2090, 5, 1), ends_on: Date.new(2090, 6, 1))
          expect(overlap).not_to be_valid
          expect(overlap.errors[:base]).to include("Term dates must not overlap another term.")
          second = create_term(starts_on: Date.new(2090, 5, 2), ends_on: Date.new(2090, 6, 1))
          expect(first.update(name: "Renamed")).to be(true)
          expect(second.update(starts_on: Date.new(2090, 4, 1))).to be(false)
     end

     it "rolls back term creation if an existing event cannot be reassigned" do
          event = session_at(Time.zone.local(2090, 9, 1))
          event.update_columns(title: "")
          expect do
               create_term(starts_on: Date.new(2090, 8, 1), ends_on: Date.new(2090, 12, 1))
          end.to raise_error(ActiveRecord::RecordInvalid)
          expect(Term.covering(event.starts_at)).to be_empty
          expect(event.reload.term).to be_nil
     end

     it "repairs legacy assignments repeatably without changing attendance" do
          term = create_term(starts_on: Date.new(2090, 8, 1), ends_on: Date.new(2090, 12, 1))
          event = session_at(Time.zone.local(2090, 9, 1))
          member = create_user
          Attendance.create!(event: event, user: member)
          event.update_columns(term_id: nil)
          term.reassign_events!
          expect(event.reload.term).to eq(term)
          expect { term.reassign_events! }.not_to change { event.reload.updated_at }
          expect(member.points_earned(term)).to eq(2)
     end

     it "installs reference terms after schema loading without overwriting named terms" do
          Term.delete_all
          load Rails.root.join("db/seeds.rb")
          expect(Term.count).to eq(3)
          Term.find_by!(name: "Fall 2026").update!(required_points: 9)
          expect { load Rails.root.join("db/seeds.rb") }.not_to change(Term, :count)
          expect(Term.find_by!(name: "Fall 2026").required_points).to eq(9)
     end

     it "searches full names, emails, terms and Central dates consistently" do
          term = create_term(name: "Review semester", starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2026, 12, 1))
          member = create_user(first_name: "Alex", last_name: "Rivera-Wellington", email: "alex.review@example.test")
          event = session_at(Time.zone.local(2026, 9, 1, 23, 30))
          Attendance.create!(event: event, user: member)
          [ "Alex Rivera-Wellington", member.email, term.name, "2026-09-01", "11:30 PM" ].each do |query|
               expect(Event.search(query, include_attendees: true)).to include(event), "Expected officer session search to match #{query.inspect}"
               expect(event.search_fields(include_attendees: true).any? { |field| field.downcase.include?(query.downcase) }).to be(true)
          end
          expect(Event.search("2026-09-02")).not_to include(event)
     end

     it "treats search wildcards literally and does not match across unrelated fields" do
          event = session_at(Time.current, title: "Workshop", location: "Room 10", notes: "100% ready_a")
          other = session_at(Time.current, notes: "100x readyza")
          expect(Event.search("100% ready_")).to contain_exactly(event)
          expect(Event.search("Workshop Room")).not_to include(event, other)
     end

     it "returns model feedback for integer overflow and zero-length sessions" do
          event = Event.new(title: "Invalid points", starts_at: Time.current, points: 2_147_483_648)
          expect(event.save).to be(false)
          expect(event.errors[:points]).to be_present
          event.points = 1
          event.ends_at = event.starts_at
          expect(event.save).to be(false)
          expect(event.errors[:ends_at]).to include("must be after the start")
     end

     it "uses preloaded RSVP and attendance without a query for each lookup" do
          member = create_user
          event = session_at(1.day.from_now)
          Rsvp.create!(event: event, user: member)
          Attendance.create!(event: event, user: member)
          loaded = Event.preload(:rsvps, :attendances).find(event.id)
          queries = []
          subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:cached] }
          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
               expect(loaded.rsvped_by?(member)).to be(true)
               expect(loaded.attended_by?(member)).to be(true)
               expect(loaded.rsvped_by?(create_user)).to be(false)
          end
          expect(queries.grep(/SELECT.*(?:rsvps|attendances)/i)).to be_empty
     end
end
