require "rails_helper"

# Exercise the real current_user/sync/role guards; only the provider boundary is stubbed.
RSpec.describe "Restricted Clerk identities", type: :request do
     let(:identity_id) { "user_synthetic_identity" }
  let(:email) { "synthetic.member@tamu.edu" }
  let(:status) { "verified" }
  let(:primary_id) { "email_primary" }
  let(:provider_email) do
       Clerk::Models::Components::EmailAddress.new(
         id: "email_primary", object: "email_address", email_address: email,
         reserved: false, linked_to: [], created_at: 0, updated_at: 0,
         verification: Clerk::Models::Components::FromOAuth.new(status: status, strategy: "oauth_google")
       )
  end
  let(:provider_user) do
       double(primary_email_address_id: primary_id, email_addresses: [ provider_email ],
         first_name: "Synthetic", last_name: "Member")
  end

  before do
       allow(User).to receive(:officer_emails).and_return([])
    proxy = double(session: { "sub" => identity_id }, user_id: identity_id, user: provider_user)
    allow_any_instance_of(ApplicationController).to receive(:clerk).and_return(proxy)
  end

  it "creates a verified TAMU member on the server" do
       expect { get profile_path }.to change(User, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(User.find_by!(clerk_user_id: identity_id)).to be_member
  end

  it "normalizes uppercase and surrounding whitespace" do
       allow(provider_email).to receive(:email_address).and_return("  SYNTHETIC.MEMBER@TAMU.EDU  ")
    get profile_path
    expect(response).to have_http_status(:ok)
    expect(User.find_by!(clerk_user_id: identity_id).email).to eq("synthetic.member@tamu.edu")
  end

  [ "synthetic@example.test", "synthetic@tamu.edu.evil.example", "synthetic@dept.tamu.edu",
    "synthetic@@tamu.edu", "synthetic tamu.edu", "@tamu.edu", "synthetic..member@tamu.edu", "", nil,
    "ptsocietytamu+preview@gmail.com", "ptsocietytamu@gmail.com.evil.example", "other@gmail.com" ].each do |denied_email|
       context "with a denied address #{denied_email.inspect}" do
            let(:email) { denied_email }

         it "rejects the session without creating an application account" do
              expect { get profile_path }.not_to change(User, :count)
           expect(response).to have_http_status(:forbidden)
           expect(response.body).to include("This email cannot access the app", "Sign out and try another email")
         end
       end
  end

  [ "unverified", "expired", nil ].each do |denied_status|
       context "with verification status #{denied_status.inspect}" do
            let(:status) { denied_status }

         it "denies even a TAMU primary email" do
              expect { get profile_path }.not_to change(User, :count)
           expect(response).to have_http_status(:forbidden)
         end
       end
  end

  it "does not fall back to a verified secondary email or a client email/role" do
       allow(provider_user).to receive(:primary_email_address_id).and_return("missing")
    expect { get profile_path, params: { email: email, email_verified: true, role: "officer" } }.not_to change(User, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "requires a primary email id" do
       allow(provider_user).to receive(:primary_email_address_id).and_return(nil)
    get profile_path
    expect(response).to have_http_status(:forbidden)
  end

  it "denies a missing provider verification object" do
       allow(provider_email).to receive(:verification).and_return(nil)
    get profile_path
    expect(response).to have_http_status(:forbidden)
  end

  it "rechecks an existing disallowed officer session without mutating its account" do
       existing = create_officer(clerk_user_id: identity_id, email: "synthetic.previous@example.test")
    allow(provider_email).to receive(:email_address).and_return(existing.email)
    original = existing.attributes
    get officer_root_path
    expect(response).to have_http_status(:forbidden)
    expect(existing.reload.attributes).to eq(original)
  end

  it "keeps an existing allowed officer authorized from stored role state" do
       create_officer(clerk_user_id: identity_id, email: email)
    get officer_root_path
    expect(response).to have_http_status(:ok)
  end

  it "denies a regular member both the officer page and a direct JSON write" do
       get officer_root_path
    expect(response).to redirect_to(root_path)
    expect { post officer_events_path, params: { event: { title: "Denied event" }, role: "officer" }, as: :json }.not_to change(Event, :count)
    expect(response).to redirect_to(root_path)
  end

  context "with the exact organization exception" do
       let(:email) { "  PTSOCIETYTAMU@GMAIL.COM  " }

    it "allows member access but denies officer pages and direct APIs even when allowlisted" do
         allow(User).to receive(:officer_emails).and_return([ email.strip.downcase ])
      get profile_path
      expect(response).to have_http_status(:ok)
      expect(User.find_by!(clerk_user_id: identity_id)).to be_member
      get officer_root_path
      expect(response).to redirect_to(root_path)
      expect { post officer_events_path, params: { event: { title: "Denied event" } }, as: :json }.not_to change(Event, :count)
      expect(response).to redirect_to(root_path)
    end

    it "removes stale officer access from an existing exception account" do
         existing = create_user(clerk_user_id: identity_id, email: email)
      existing.update_column(:role, User.roles.fetch("officer"))
      get officer_root_path
      expect(response).to redirect_to(root_path)
      expect(existing.reload).to be_member
    end

    it "requires verification for the exception too" do
         allow(provider_email.verification).to receive(:status).and_return("unverified")
      get profile_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "does not let direct sync bypass verification" do
       expect {
            User.sync_from_clerk(clerk_user_id: identity_id, email: email)
       }.to raise_error(User::EmailDomainNotAllowed)
  end

  it "does not echo private fields in the denial page" do
       allow(provider_email).to receive(:email_address).and_return("synthetic.denied@example.test")
    get profile_path
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include("synthetic.denied@example.test", identity_id)
  end
end
