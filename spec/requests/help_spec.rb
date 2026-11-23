require "rails_helper"

RSpec.describe "Help", type: :request do
     def page
          Nokogiri::HTML(response.body)
     end

  it "sends visitors to sign in" do
       get help_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end

  it "is in the name menu" do
       sign_in_as(create_user)

    get root_path

    expect(page.at("details.account-menu a[href='#{help_path}']").text).to eq("Help")
  end

  it "is not offered to visitors" do
       get root_path

    expect(response.body).not_to include(%(href="#{help_path}"))
  end

  it "shows members the member guide only" do
       sign_in_as(create_user)

    get help_path

    expect(response).to have_http_status(:ok)
    expect(page.at("#member-guide h2").text).to eq("User Guide (Members)")
    expect(page.at("#member-guide").text).to include("Event board", "Announcements about your points")
    expect(page.at("#officer-guide")).to be_nil
    expect(response.body).not_to include("Administrator Guide", "Taking attendance", "OFFICER_EMAILS")
  end

  it "shows officers both guides and a way to jump between them" do
       sign_in_as(create_officer)

    get help_path

    expect(page.at("#officer-guide").text).to include("Administrator Guide (Officers)", "Taking attendance")
    expect(page.at("#member-guide").text).to include("User Guide (Members)")
    expect(page.css("nav[aria-label='Guides'] a").map { |link| link["href"] }).to eq([ "#officer-guide", "#member-guide" ])
  end

  it "renders the guides as a page, without what only works in the repository" do
       sign_in_as(create_officer)

    get help_path

    main = page.at("main")
    expect(main.css("h1").size).to eq(1)
    expect(main.css("h3").map(&:text)).to include("Sign in", "Posting an event")
    expect(main.css("pre code").text).to include("OFFICER_EMAILS=")
    expect(main.css("a[href$='.md']")).to be_empty
    expect(main.text).not_to include("SUPPORT.md")
    expect(main.css("h3").map(&:text)).not_to include("Questions", "Support")
    expect(main.css("li br, p br")).to be_empty
    ids = main.css("[id]").map { |element| element["id"] }
    expect(ids).to eq(ids.uniq)
  end
end
