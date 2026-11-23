require "rails_helper"

RSpec.describe "Officer terms", type: :request do
     let(:officer) { create_officer }
  let(:member) { create_user }
  let(:term_attributes) do
       {
         name: "Fall 2099",
         starts_on: Date.new(2099, 8, 20),
         ends_on: Date.new(2099, 12, 15),
         required_points: 8,
         required_professional_points: 2,
         required_social_points: 1
       }
  end

  it "lists terms with the current one marked" do
       current = create_current_term
    sign_in_as(officer)

    get officer_terms_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current.name, "current", "Add a term")
  end

  it "creates a term and its events are assigned" do
       event = Event.create!(title: "Future clinic", starts_at: Time.zone.local(2099, 9, 1), points: 1)
    sign_in_as(officer)

    expect {
         post officer_terms_path, params: { term: term_attributes }
    }.to change(Term, :count).by(1)

    expect(response).to redirect_to(officer_terms_path)
    expect(event.reload.term).to eq(Term.last)
  end

  it "shows validation errors and saves nothing for overlapping dates" do
       create_term(name: "Existing term", starts_on: Date.new(2099, 8, 1), ends_on: Date.new(2099, 12, 31))
    sign_in_as(officer)

    expect {
         post officer_terms_path, params: { term: term_attributes }
    }.not_to change(Term, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Term dates must not overlap another term.")
  end

  it "updates a term and reassigns events" do
       term = create_term(name: "Editable", starts_on: Date.new(2099, 8, 1), ends_on: Date.new(2099, 9, 30))
    event = Event.create!(title: "Moved clinic", starts_at: Time.zone.local(2099, 9, 15), points: 1)
    sign_in_as(officer)

    patch officer_term_path(term), params: { term: { ends_on: Date.new(2099, 9, 14) } }

    expect(response).to redirect_to(officer_terms_path)
    expect(term.reload.ends_on).to eq(Date.new(2099, 9, 14))
    expect(event.reload.term).to be_nil
  end

  it "does not let members manage terms" do
       sign_in_as(member)

    get officer_terms_path
    expect(response).to redirect_to(root_path)

    expect {
         post officer_terms_path, params: { term: term_attributes }
    }.not_to change(Term, :count)
  end

  it "sends visitors to sign in" do
       get new_officer_term_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end
end
