require "rails_helper"
require "csv"

RSpec.describe "Officer attendance imports", type: :request do
     let(:officer) { create_officer }
  let(:event) do
       Event.create!(title: "General Meeting", starts_at: Time.zone.local(2026, 10, 6, 21),
                     ends_at: Time.zone.local(2026, 10, 6, 22), points: 1, category: :general, created_by: officer)
  end
  let!(:ada) { create_user(email: "ada@example.com") }
  let!(:grace) { create_user(email: "grace@example.com") }

  # Every officer check goes through current_user, so signing in only needs that one method.
  def sign_in_as(user)
       allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  def csv_upload(*emails)
       csv = CSV.generate do |rows|
            rows << [ "Checked In", "Email" ]
         emails.each { |email| rows << [ "10/06/2026 10:33 PM", email ] }
       end
    Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "attendance.csv")
  end

  def import(*emails)
       post officer_event_attendance_import_path(event), params: { file: csv_upload(*emails) }
  end

  context "when signed in as an officer" do
       before { sign_in_as(officer) }

    it "marks the listed members present and redirects back to the event with a notice" do
         expect { import(ada.email, grace.email) }.to change(Attendance, :count).by(2)
      expect(response).to redirect_to(officer_event_path(event))
      expect(flash[:notice]).to eq("Marked 2 present; 0 already recorded.")
      expect(flash[:import_errors]).to be_nil
    end

    it "reports how many people were already recorded" do
         Attendance.create!(event: event, user: ada, recorded_by: officer)
      expect { import(ada.email, grace.email) }.to change(Attendance, :count).by(1)
      expect(flash[:notice]).to eq("Marked 1 present; 1 already recorded.")
    end

    it "redirects back with the problems and imports nothing when an email has no member" do
         expect { import(ada.email, "nobody@example.com") }.not_to change(Attendance, :count)
      expect(response).to redirect_to(officer_event_path(event))
      expect(flash[:import_errors]).to eq([ "Row 3: No member has the email nobody@example.com." ])
      expect(flash[:notice]).to be_nil
    end

    it "redirects back with an error when no file was chosen" do
         expect { post officer_event_attendance_import_path(event) }.not_to change(Attendance, :count)
      expect(response).to redirect_to(officer_event_path(event))
      expect(flash[:import_errors]).to eq([ "Choose the GetInvolved Excel (.xlsx) export or a CSV UTF-8 file." ])
    end

    it "keeps the error list short enough for the session cookie" do
         import(*(1..22).map { |n| "nobody#{n}@example.com" })
      errors = flash[:import_errors]
      expect(errors.size).to eq(11)
      expect(errors.first).to eq("Row 2: No member has the email nobody1@example.com.")
      expect(errors.last).to eq("...and 11 more.")
    end

    it "shortens very long error lines" do
         import("#{'a' * 200}@example.com")
      expect(flash[:import_errors].first.length).to be <= 120
    end
  end

  context "when signed in as a regular member" do
       before { sign_in_as(create_user) }

    it "is turned away and imports nothing" do
         expect { import(ada.email) }.not_to change(Attendance, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("That area is for officers.")
    end
  end

  context "when signed out" do
       before { sign_in_as(nil) }

    it "is asked to sign in and imports nothing" do
         expect { import(ada.email) }.not_to change(Attendance, :count)
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Please sign in.")
    end
  end
end
