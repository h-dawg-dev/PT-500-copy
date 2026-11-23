require "rails_helper"

RSpec.describe PointAdjustment, type: :model do
     let(:term) { create_current_term }
     let(:officer) { create_officer }
     let(:member) { create_user(first_name: "Manny", last_name: "Member") }

     def build_adjustment(attrs = {})
          PointAdjustment.new({ user: member, term: term, recorded_by: officer, points: 2, category: :general, reason: "Missed check-in." }.merge(attrs))
     end

     def errors_for(adjustment)
          adjustment.validate
          adjustment.errors.full_messages
     end

     def attend(points:, category:)
          event = Event.create!(title: "Session", starts_at: 1.day.ago, points: points, category: category, created_by: officer)
          Attendance.create!(event: event, user: member, recorded_by: officer)
     end

     # O14.1
     it "is valid with a member, term, whole-number amount, category and reason" do
          attend(points: 1, category: :social)

          expect(build_adjustment).to be_valid
          expect(build_adjustment(points: -1, category: :social)).to be_valid
     end

     # O14.2
     it "requires a whole, non-zero amount" do
          {
               nil => "Amount is required. Enter a whole number of points, such as 2 or -2",
               "1.5" => "Amount must be a whole number, such as 2 or -2",
               "abc" => "Amount must be a whole number, such as 2 or -2",
               0 => "Amount can't be zero. Enter a positive number to add points or a negative number to subtract"
          }.each do |points, message|
               expect(errors_for(build_adjustment(points: points))).to eq([ message ])
          end
     end

     # O14.2
     it "requires one of the session categories" do
          expect(errors_for(build_adjustment(category: nil))).to eq([ "Category is required. Choose general, professional, or social" ])
          expect(errors_for(build_adjustment(category: "bogus"))).to eq([ "Category is not included in the list" ])
     end

     # O14.1: the reason
     it "requires a reason of reasonable length and trims it" do
          expect(errors_for(build_adjustment(reason: " "))).to eq([ "Reason is required. Say why the points are changing" ])
          expect(build_adjustment(reason: "x" * (PointAdjustment::REASON_MAX_LENGTH + 1))).not_to be_valid
          expect(build_adjustment(reason: "  Missed check-in.  ").reason).to eq("Missed check-in.")
     end

     # O14.3
     it "cannot give points to an officer" do
          adjustment = build_adjustment(user: create_officer)

          expect(errors_for(adjustment)).to eq([ "Officers are not part of the points system, so they can't be given points." ])
     end

     # O14.4
     it "needs a term to belong to" do
          expect(errors_for(build_adjustment(term: nil))).to eq([ "No term covers today, so there is no current semester to adjust. Ask an administrator to set the term dates." ])
     end

     # Extra safeguard beyond O14: totals never go below zero
     it "cannot take a category below zero for the term" do
          attend(points: 2, category: :professional)

          expect(build_adjustment(points: -2, category: :professional)).to be_valid
          expect(errors_for(build_adjustment(points: -3, category: :professional))).to eq([
               "Manny Member has only 2 professional points in #{term.name}, so you can subtract at most 2."
          ])
          expect(errors_for(build_adjustment(points: -1, category: :social))).to eq([ "Manny Member has no social points in #{term.name} to subtract." ])
     end

     # Extra safeguard beyond O14: totals never go below zero
     it "counts earlier adjustments when checking what can be subtracted" do
          build_adjustment(points: 3).save!

          expect(build_adjustment(points: -3)).to be_valid
          expect(build_adjustment(points: -4)).not_to be_valid
     end

     # O14.4
     it "scopes to a term, or everything for all time" do
          past = create_term(name: "Past", starts_on: term.starts_on - 200.days, ends_on: term.starts_on - 100.days)
          current = build_adjustment.tap(&:save!)
          earlier = build_adjustment(term: past).tap(&:save!)

          expect(PointAdjustment.for_period(term)).to contain_exactly(current)
          expect(PointAdjustment.for_period(past)).to contain_exactly(earlier)
          expect(PointAdjustment.for_period(nil)).to contain_exactly(current, earlier)
     end

     # U12.1, U12.2
     it "counts a change as unseen until the member dismisses its announcement" do
          change = build_adjustment.tap(&:save!)
          seen = build_adjustment(seen_at: Time.current).tap(&:save!)

          expect(change.seen_at).to be_nil
          expect(PointAdjustment.unseen).to contain_exactly(change)
          expect(PointAdjustment.unseen).not_to include(seen)
     end

     # O14.4
     it "keeps a term with adjustments from being deleted" do
          build_adjustment.save!

          expect(term.destroy).to be(false)
          expect(Term.exists?(term.id)).to be(true)
     end
end
