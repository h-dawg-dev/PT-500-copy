require "rails_helper"

RSpec.describe AppSetting, type: :model do
     it "requires the email policy by default" do
          expect(AppSetting.require_tamu_email?).to be(true)
     end

  it "persists the TAMU-only signup rule" do
       AppSetting.require_tamu_email = true

    expect(AppSetting.require_tamu_email?).to be(true)
    expect(AppSetting.current.reload.require_tamu_email).to be(true)
  end

  it "lets officers turn the @tamu.edu requirement off and on" do
       AppSetting.require_tamu_email = false
       expect(AppSetting.current.reload.require_tamu_email).to be(false)
       AppSetting.require_tamu_email = true
       expect(AppSetting.current.reload.require_tamu_email).to be(true)
  end
end
