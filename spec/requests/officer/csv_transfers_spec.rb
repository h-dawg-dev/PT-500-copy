require "rails_helper"
require "csv"

RSpec.describe "Officer CSV transfers", type: :request do
     include ActiveSupport::Testing::TimeHelpers
     let(:officer) { create_officer }

     it "protects the page, import and every report from members and anonymous users" do
          [ nil, create_user ].each do |user|
               sign_in_as(user)
               get officer_csv_transfer_path
               expect(response).to have_http_status(:redirect)
               expect { post officer_csv_transfer_path }.not_to change(Event, :count)
               expect(response).to have_http_status(:redirect)
               %w[events attendances members].each do |report|
                    get export_officer_csv_transfer_path, params: { report: report, term_id: "all" }
                    expect(response).to have_http_status(:redirect)
                    expect(response.media_type).not_to eq("text/csv")
               end
          end
     end

     it "renders upload and report forms for officers" do
          sign_in_as(officer)
          get officer_csv_transfer_path
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Excel (.xlsx)", "No conversion is needed", ".xlsx,", "Import events", "Download CSV")
     end

     it "explains that an upload interrupted by sign-in refresh must be retried" do
          sign_in_as(officer)
          expect { get officer_csv_transfer_path, params: { retry_import: "1" } }.not_to change(Event, :count)
          expect(response.body).to include("Your sign-in was refreshed", "No events were imported")
     end

     it "imports a real multipart CSV upload, then downloads the event report" do
          sign_in_as(officer)
          csv = CSV.generate do |file|
               file << GetinvolvedEventImport::HEADERS
               file << [ "EVN-123", "Event", "Workshop", "PTS", "Oct 14, 2026 4:30 pm", "Oct 14, 2026 6:00 pm", "Submitted", "Rudder" ]
          end
          Tempfile.create([ "getinvolved", ".csv" ]) do |file|
               file.write(csv)
               file.flush
               upload = Rack::Test::UploadedFile.new(file.path, "text/csv")
               expect { post officer_csv_transfer_path, params: { file: upload } }.to change(Event, :count).by(1)
          end
          expect(response).to redirect_to(officer_csv_transfer_path)
          follow_redirect!
          expect(response.body).to include("Imported 1 events")
          get export_officer_csv_transfer_path, params: { report: "events", term_id: "all" }
          expect(response.media_type).to eq("text/csv")
          expect(response.headers["Content-Disposition"]).to include("attachment", ".csv")
          expect(response.headers["Cache-Control"]).to include("no-store")
          expect(response.body).to start_with("\uFEFF")
          expect(CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true).first["GetInvolved Reference"]).to eq("EVN-123")
     end

     it "imports the GetInvolved Excel export directly as a multipart upload" do
          sign_in_as(officer)
          rows = [ [ "EVN-456", "Event", "Excel Workshop", "PTS", "Nov 6, 2026 6:00 pm", "Nov 6, 2026 8:00 pm", "Submitted", nil, "PEAP Building" ] ]
          Tempfile.create([ "getinvolved", ".xlsx" ]) do |file|
               file.binmode
               file.write(getinvolved_workbook(rows))
               file.flush
               upload = Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", true)
               expect { post officer_csv_transfer_path, params: { file: upload } }.to change(Event, :count).by(1)
               expect(response).to redirect_to(officer_csv_transfer_path)
               expect { post officer_csv_transfer_path, params: { file: upload } }.not_to change(Event, :count)
          end
          follow_redirect!
          expect(response.body).to include("skipped 1 existing references")
          expect(Event.find_by!(getinvolved_reference: "EVN-456").location).to eq("PEAP Building")
     end

     it "reports a corrupt Excel upload without importing events" do
          sign_in_as(officer)
          Tempfile.create([ "broken", ".xlsx" ]) do |file|
               file.write("PKbroken")
               file.flush
               upload = Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", true)
               expect { post officer_csv_transfer_path, params: { file: upload } }.not_to change(Event, :count)
          end
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include("valid Excel (.xlsx)")
     end

     it "returns useful errors for absent and forged uploads" do
          sign_in_as(officer)
          [ nil, "forged" ].each do |file|
               expect { post officer_csv_transfer_path, params: { file: file } }.not_to change(Event, :count)
               expect(response).to have_http_status(:unprocessable_entity)
               expect(response.body).to include("Choose the GetInvolved Excel")
          end
     end

     it "defaults to the current term and rejects unknown reports or term IDs" do
          sign_in_as(officer)
          term = create_term
          Event.create!(title: "Current", starts_at: Time.zone.local(2026, 9, 22), created_by: officer)
          Event.create!(title: "Outside", starts_at: Time.zone.local(2027, 1, 1), created_by: officer)
          travel_to Time.zone.local(2026, 10, 1) do
               get export_officer_csv_transfer_path, params: { report: "events" }
               rows = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
               expect(rows.map { |row| row["Title"] }).to eq([ "Current" ])
               expect(rows.first["Term"]).to eq(term.name)
          end
          get export_officer_csv_transfer_path, params: { report: "not_a_report" }
          expect(response).to have_http_status(:not_found)
          get export_officer_csv_transfer_path, params: { report: "events", term_id: "99999999" }
          expect(response).to have_http_status(:not_found)
     end
end
