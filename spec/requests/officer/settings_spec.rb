require "rails_helper"

RSpec.describe "Officer society settings", type: :request do
     let(:officer) { create_officer }
  let(:member) { create_user }

  it "shows the signup rule to officers" do
       sign_in_as(officer)

    get officer_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Society settings", "Email access policy", "ptsocietytamu@gmail.com", "Only allow")
  end

  it "lets officers turn the @tamu.edu requirement off and back on" do
       sign_in_as(officer)

    patch officer_settings_path, params: { app_setting: { require_tamu_email: "0" } }

    expect(response).to redirect_to(officer_settings_path)
    expect(AppSetting.require_tamu_email?).to be(false)
    follow_redirect!
    expect(response.body).to include("not required right now")

    patch officer_settings_path, params: { app_setting: { require_tamu_email: "1" } }

    expect(AppSetting.require_tamu_email?).to be(true)
  end

  it "does not let members change the signup rule" do
       sign_in_as(member)

    patch officer_settings_path, params: { app_setting: { require_tamu_email: "1" } }

    expect(response).to redirect_to(root_path)
    expect(AppSetting.require_tamu_email?).to be(true)
  end

  it "sends visitors to sign in" do
       get officer_settings_path

    expect(response).to be_redirect
    expect(response.location).to include("example.com/sign-in")
  end
end
