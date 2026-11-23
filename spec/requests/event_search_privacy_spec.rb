require "rails_helper"

RSpec.describe "Event search privacy", type: :request do
     let(:officer) { create_officer }
     let(:member) { create_user }
     let(:attendee) { create_user(first_name: "Private", last_name: "Attendee-unique", email: "private-attendee-unique@example.test") }
     let!(:event) do
          posted = Event.create!(title: "Open workshop", location: "Room 29", notes: "Bring a notebook", starts_at: 1.hour.from_now, created_by: officer)
          Attendance.create!(event: posted, user: attendee, recorded_by: officer)
          posted
     end

     it "omits other attendees' contact data from the member board and home page" do
          sign_in_as(member)

          [ events_path, root_path ].each do |path|
               get path

               expect(response).to have_http_status(:ok)
               expect(response.body).not_to include(attendee.email, attendee.display_name)
               fields = Nokogiri::HTML(response.body).css("[data-search-fields]").flat_map { |element| JSON.parse(element["data-search-fields"]) }
               expect(fields).to include(event.title)
               expect(fields).not_to include(attendee.email, attendee.display_name)
          end
     end

     it "does not let member searches infer attendance by name or email, even with a forged option" do
          sign_in_as(member)

          [ attendee.email, attendee.display_name ].each do |query|
               get events_path, params: { q: query, filter: "all", include_attendees: true }

               expect(response).to have_http_status(:ok)
               expect(Nokogiri::HTML(response.body).css("article.slot")).to be_empty
          end
     end

     it "retains member searches by public event fields" do
          sign_in_as(member)

          [ event.title, event.location, event.notes, event.starts_at.in_time_zone.to_date.iso8601 ].each do |query|
               get events_path, params: { q: query }

               expect(Nokogiri::HTML(response.body).css("article.slot h3").map(&:text)).to include(event.title)
          end
     end

     it "retains officer attendee searches and contact metadata on both boards" do
          sign_in_as(officer)

          [ officer_events_path, events_path ].each do |path|
               get path, params: { q: attendee.email }

               expect(response).to have_http_status(:ok)
               expect(response.body).to include(event.title, attendee.email)
          end
     end

     it "keeps model search and metadata safe unless attendee access is explicitly requested" do
          expect(Event.search(attendee.email)).to be_empty
          expect(Event.search(attendee.display_name)).to be_empty
          expect(event.search_fields).not_to include(attendee.email, attendee.display_name)
          expect(event.search_text).not_to include(attendee.email, attendee.display_name)
          expect(Event.search(attendee.email, include_attendees: true)).to include(event)
     end
end
