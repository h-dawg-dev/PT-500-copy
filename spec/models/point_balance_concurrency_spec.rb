require "rails_helper"

RSpec.describe "Concurrent point changes", type: :model do
     self.use_transactional_tests = false

     before do
          @owned_term = Term.current.nil?
          @term = create_current_term
          @officer = create_officer
          @member = create_user
          @events = []
     end

     after do
          ids = [ @member&.id, @officer&.id ].compact
          PointAdjustment.where(user_id: ids).delete_all
          Attendance.where(user_id: ids).delete_all
          Event.where(id: @events.map(&:id)).delete_all
          User.where(id: ids).delete_all
          @term&.delete if @owned_term
     end

     def credit
          event = Event.create!(title: "Concurrent credit", starts_at: Time.current, points: 3, created_by: @officer)
          @events << event
          Attendance.create!(event: event, user: @member, recorded_by: @officer)
          event
     end

     def race(*operations)
          ready = Queue.new
          start = Queue.new
          threads = operations.map do |operation|
               Thread.new do
                    ActiveRecord::Base.connection_pool.with_connection do |connection|
                         ready << true
                         start.pop
                         connection.transaction do
                              connection.execute("SET LOCAL lock_timeout = '5s'")
                              operation.call
                         end
                    end
               end
          end
          operations.size.times { ready.pop }
          operations.size.times { start << true }
          threads.map(&:value)
        ensure
             threads&.each(&:join)
     end

     it "does not let a deduction and an event edit spend the same credit" do
          event = credit

          results = race(
            -> { Event.find(event.id).update(points: 0) },
            -> { PointAdjustment.new(user_id: @member.id, term_id: @term.id, recorded_by_id: @officer.id, points: -2, category: :general, reason: "Concurrent deduction").save }
          )

          expect(results.count(true)).to eq(1)
          expect(@member.reload.points_by_category(@term)["general"]).to be >= 0
     end

     it "serializes edits to different events that affect the same member balance" do
          first = credit
          second = credit
          PointAdjustment.create!(user: @member, term: @term, recorded_by: @officer, points: -4, category: :general, reason: "Correction")

          results = race(
            -> { Event.find(first.id).update(points: 1) },
            -> { Event.find(second.id).update(points: 1) }
          )

          expect(results.count(true)).to eq(1)
          expect(@member.reload.points_by_category(@term)["general"]).to eq(0)
     end
end
