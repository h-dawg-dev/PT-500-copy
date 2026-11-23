require "rails_helper"
require "csv"

RSpec.describe GetinvolvedEventImport do
     let(:officer) { create_officer }
     let(:rows) do
          [
            [ "EVN-26994", "Event", "General Meeting", "Physical Therapy Society", "Sep 22, 2026 7:00 pm", "Sep 22, 2026 8:00 pm", "Initiated", "Memorial Student Center", "MSC 2406A", "", "None", "Planner" ],
            [ "EVN-27798", "Event", "Skills Workshop", "Physical Therapy Society", "Oct 14, 2026 4:30 pm", "Oct 14, 2026 6:00 pm", "Submitted", "Rudder", "", "Texas A&amp;M, CPR\nand blood pressure.", "None", "Planner" ],
            [ "EVN-26955", "Event", "Pickleball Tournament", "Physical Therapy Society", "Oct 18, 2026 6:00 am", "Oct 18, 2026 4:00 pm", "Approved", "", "PEAP Building", "Fundraiser", "None", "Planner" ],
            [ "EVN-27792", "Event", "Splinting Workshop", "Physical Therapy Society", "Nov 6, 2026 6:00 pm", "Nov 6, 2026 8:00 pm", "Submitted", "Memorial Student Center", "", "Splints &amp; slings", "None", "Planner" ]
          ]
     end

     def import(data = rows, headers: described_class::HEADERS, format: :xlsx)
          content = if format == :csv
               "\uFEFF#{CSV.generate { |csv| csv << headers; data.each { |row| csv << row } }}"
          else
               getinvolved_workbook(data, headers: headers)
          end
          described_class.new(file: StringIO.new(content), officer: officer).call
     end

     it "imports the supplied worksheet shape in Central time without awarding attendance or points" do
          term = create_term
          result = import
          expect(result).to be_success
          expect(result.created_count).to eq(4)
          expect(result.skipped_count).to eq(0)
          events = Event.order(:starts_at)
          expect(events.map(&:term)).to eq([ term ] * 4)
          expect(events.map(&:points)).to eq([ 1 ] * 4)
          expect(events.map(&:category).uniq).to eq([ "general" ])
          expect(events.map(&:created_by).uniq).to eq([ officer ])
          expect(events.first.starts_at).to eq(Time.zone.local(2026, 9, 22, 19))
          expect(events.last.starts_at).to eq(Time.zone.local(2026, 11, 6, 18))
          expect(events.first.location).to eq("Memorial Student Center - MSC 2406A")
          expect(events.third.location).to eq("PEAP Building")
          expect(events.second.notes).to eq("Texas A&M, CPR\nand blood pressure.")
          expect(events.second.getinvolved_data["Status"]).to eq("Submitted")
          expect(Attendance.count).to eq(0)
     end

     it "keeps accepting CSV UTF-8 exports" do
          expect(import(format: :csv).created_count).to eq(4)
          expect(import(format: :csv).skipped_count).to eq(4)
     end

     it "preserves missing Excel cells and reads native Excel timestamps in Central time" do
          rows.first[4] = DateTime.new(2026, 9, 22, 19)
          rows.first[5] = DateTime.new(2026, 9, 22, 20)
          rows.third[7] = nil
          rows.second[8] = nil
          result = import
          expect(result).to be_success
          expect(Event.find_by!(getinvolved_reference: "EVN-26994").starts_at).to eq(Time.zone.local(2026, 9, 22, 19))
          expect(Event.find_by!(getinvolved_reference: "EVN-26955").location).to eq("PEAP Building")
          expect(Event.find_by!(getinvolved_reference: "EVN-27798").notes).to eq("Texas A&M, CPR\nand blood pressure.")
     end

     it "rejects corrupt, empty, multi-sheet and oversized expanded workbooks without writes" do
          files = [ "PKbroken", getinvolved_workbook([], headers: []), getinvolved_workbook(rows, sheets: 2) ]
          files.each do |content|
               expect { @result = described_class.new(file: StringIO.new(content), officer: officer).call }.not_to change(Event, :count)
               expect(@result).not_to be_success
          end
          stub_const("GetinvolvedEventImport::MAX_EXPANDED_BYTES", 100)
          expect { @result = import }.not_to change(Event, :count)
          expect(@result.errors.join).to include("expands beyond")
     end

     it "rejects a header-only workbook" do
          expect(import([]).errors.join).to include("no event rows")
     end

     it "skips existing references and preserves officer edits and attendance" do
          import
          event = Event.find_by!(getinvolved_reference: "EVN-26994")
          event.update!(title: "Edited locally", points: 3, category: :professional)
          attendance = Attendance.create!(event: event, user: create_user, recorded_by: officer)
          result = import
          expect(result).to be_success
          expect(result.created_count).to eq(0)
          expect(result.skipped_count).to eq(4)
          expect(event.reload.attributes.values_at("title", "points", "category")).to eq([ "Edited locally", 3, "professional" ])
          expect(attendance.reload.event).to eq(event)
     end

     it "rolls back the whole file if a later row is invalid" do
          rows.last[5] = "Nov 6, 2026 5:00 pm"
          expect { @result = import }.not_to change(Event, :count)
          expect(@result.errors.join).to include("Row 5", "must be after the start")
     end

     it "rejects duplicate references within a file" do
          rows.last[0] = rows.first[0]
          expect { @result = import }.not_to change(Event, :count)
          expect(@result.errors.join).to include("appears more than once")
     end

     it "rejects missing or duplicate headers" do
          expect(import(headers: described_class::HEADERS.drop(1)).errors.join).to include("Missing columns: Reference")
          expect(import(headers: described_class::HEADERS + [ "Title" ]).errors.join).to include("must not be repeated")
     end

     it "rejects impossible dates and non-event rows" do
          rows.first[4] = "Feb 30, 2026 7:00 pm"
          expect(import.errors.join).to include("Row 2")
          rows.first[4] = "Sep 22, 2026 7:00 pm"
          rows.first[1] = "Organization"
          expect(import.errors.join).to include("Type must be Event")
     end

     it "reports malformed, empty, non-UTF-8 and oversized uploads without writing events" do
          [ StringIO.new('Reference,Type,Title,Starts,Ends\n"unterminated'), StringIO.new(""),
           StringIO.new("\xFF".b), StringIO.new("x" * (described_class::MAX_BYTES + 1)), "forged upload", nil ].each do |file|
               expect(described_class.new(file: file, officer: officer).call).not_to be_success
          end
          expect(Event.count).to eq(0)
     end

     it "limits row count before saving any events" do
          stub_const("GetinvolvedEventImport::MAX_ROWS", 2)
          expect { @result = import }.not_to change(Event, :count)
          expect(@result.errors.join).to include("at most 2")
     end

     it "rolls back earlier saves if another import wins a reference race" do
          allow_any_instance_of(Event).to receive(:save!).and_call_original
          allow_any_instance_of(Event).to receive(:save!).with(no_args) do |event|
               raise ActiveRecord::RecordNotUnique if event.getinvolved_reference == "EVN-27798"

               event.save
          end
          expect { @result = import }.not_to change(Event, :count)
          expect(@result).not_to be_success
     end
end
