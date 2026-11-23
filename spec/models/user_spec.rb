require "rails_helper"

RSpec.describe User, type: :model do
  def build_user(attrs = {})
    User.new({
      clerk_user_id: "user_#{SecureRandom.hex(4)}",
      email: "member@example.com",
      first_name: "Hudson",
      last_name: "Lee"
    }.merge(attrs))
  end

  it "is valid with a clerk id and email" do
    expect(build_user).to be_valid
  end

  it "is invalid without a clerk user id" do
    user = build_user(clerk_user_id: nil)
    expect(user).not_to be_valid
    expect(user.errors[:clerk_user_id]).to include("can't be blank")
  end

  it "is invalid without an email" do
    user = build_user(email: nil)
    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end

  it "defaults new users to the member role" do
    user = build_user
    user.valid?
    expect(user.role).to eq("member")
    expect(user).to be_member
    expect(user).not_to be_officer
  end

  it "can be an officer" do
    user = build_user(role: :officer)
    expect(user).to be_officer
  end

  it "requires a unique clerk user id" do
    existing = build_user(clerk_user_id: "user_abc", email: "one@example.com")
    existing.save!
    duplicate = build_user(clerk_user_id: "user_abc", email: "two@example.com")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:clerk_user_id]).to include("has already been taken")
  end

  it "stores emails in lowercase without surrounding space" do
    user = build_user(email: "  Hudson.QML@tamu.edu  ")
    user.valid?
    expect(user.email).to eq("hudson.qml@tamu.edu")
  end

  it "requires a unique email regardless of case" do
    build_user(clerk_user_id: "user_one", email: "iris@example.com").save!
    duplicate = build_user(clerk_user_id: "user_two", email: "IRIS@example.com")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to include("has already been taken")
  end

  describe ".sync_from_clerk" do
    it "creates a member from Clerk attributes" do
      user = User.sync_from_clerk(email_verified: true,
        clerk_user_id: "user_new",
        email: "iris@tamu.edu",
        first_name: "Iris",
        last_name: "Klingbeil"
      )

      expect(user).to be_persisted
      expect(user.email).to eq("iris@tamu.edu")
      expect(user.first_name).to eq("Iris")
      expect(user).to be_member
    end

    it "updates profile fields on later sign-ins without demoting officers" do
      user = User.sync_from_clerk(email_verified: true,
        clerk_user_id: "user_keep",
        email: "officer@tamu.edu",
        first_name: "Pat"
      )
      user.update!(role: :officer)

      updated = User.sync_from_clerk(email_verified: true,
        clerk_user_id: "user_keep",
        email: "officer@tamu.edu",
        first_name: "Patricia"
      )

      expect(updated.id).to eq(user.id)
      expect(updated.first_name).to eq("Patricia")
      expect(updated).to be_officer
    end

    it "promotes users whose email is listed in OFFICER_EMAILS" do
      allow(User).to receive(:officer_emails).and_return([ "hudson.qml@tamu.edu" ])

      user = User.sync_from_clerk(email_verified: true,
        clerk_user_id: "user_pres",
        email: "Hudson.QML@tamu.edu",
        first_name: "Hudson"
      )

      expect(user).to be_officer
    end

    it "does nothing without a clerk user id" do
      expect(User.sync_from_clerk(email_verified: true, email: "nobody@example.com")).to be_nil
      expect { User.sync_from_clerk(email_verified: true, clerk_user_id: "") }.not_to change(User, :count)
    end

    context "when TAMU-only signups are required" do
      before { AppSetting.require_tamu_email = true }

      it "rejects a new non-TAMU account without creating a record" do
        expect {
          User.sync_from_clerk(email_verified: true, clerk_user_id: "user_outside", email: "alex@example.com")
        }.to raise_error(User::EmailDomainNotAllowed, User::EMAIL_DOMAIN_MESSAGE)
        expect(User.find_by(clerk_user_id: "user_outside")).to be_nil
      end

      it "accepts a new TAMU account regardless of case" do
        user = User.sync_from_clerk(email_verified: true, clerk_user_id: "user_inside", email: "Alex.Rivera@TAMU.edu")

        expect(user).to be_persisted
        expect(user.email).to eq("alex.rivera@tamu.edu")
      end

      it "rejects an existing non-TAMU account without changing its record" do
        existing = User.create!(
          clerk_user_id: "user_legacy",
          email: "legacy@example.com",
          first_name: "Legacy"
        )

        original = existing.attributes
        expect {
          User.sync_from_clerk(email_verified: true, clerk_user_id: existing.clerk_user_id, email: existing.email)
        }.to raise_error(User::EmailDomainNotAllowed)
        expect(existing.reload.attributes).to eq(original)
      end

      it "does not let OFFICER_EMAILS bypass the email restriction" do
        allow(User).to receive(:officer_emails).and_return([ "advisor@example.com" ])

        expect {
          User.sync_from_clerk(email_verified: true, clerk_user_id: "user_officer", email: "advisor@example.com")
        }.to raise_error(User::EmailDomainNotAllowed)
      end
    end
  end

  describe ".email_allowed_for_signup?" do
    it "accepts any valid address only when the TAMU requirement is off" do
      expect(User.email_allowed_for_signup?("me@gmail.com")).to be(false)
      AppSetting.require_tamu_email = false
      expect(User.email_allowed_for_signup?("me@gmail.com")).to be(true)
      expect(User.email_allowed_for_signup?("not-an-email")).to be(false)
    end
  end

  describe ".tamu_email?" do
    it "accepts only addresses at the tamu.edu domain" do
      expect(User.tamu_email?("student@tamu.edu")).to be(true)
      expect(User.tamu_email?(" Student@TAMU.EDU ")).to be(true)
      expect(User.tamu_email?("student@student.tamu.edu")).to be(false)
      expect(User.tamu_email?("student@tamu.edu.example.com")).to be(false)
      expect(User.tamu_email?("student@example.com")).to be(false)
      expect(User.tamu_email?(nil)).to be(false)
    end
  end

  describe ".email_from_clerk_user" do
    it "prefers the primary email address" do
      clerk_user = double(
        primary_email_address_id: "idn_2",
        email_addresses: [
          double(id: "idn_1", email_address: "old@example.com", verification: double(status: "verified")),
          double(id: "idn_2", email_address: "primary@example.com", verification: double(status: "verified"))
        ]
      )

      expect(User.email_from_clerk_user(clerk_user)).to eq("primary@example.com")
    end

    it "rejects a provider user without a primary email id" do
      clerk_user = double(
        primary_email_address_id: nil,
        email_addresses: [
          double(id: "idn_1", email_address: "first@example.com")
        ]
      )

      expect(User.email_from_clerk_user(clerk_user)).to be_nil
    end

    it "returns nothing when Clerk sent no user" do
      expect(User.email_from_clerk_user(nil)).to be_nil
    end
  end

  describe "profile information" do
    def profile_user(attrs = {})
      build_user({ major: "Kinesiology", class_year: Date.current.year + 1, tshirt_size: "M" }.merge(attrs))
    end

    it "is not required outside the profile form, so first sign-in still saves" do
      expect(build_user).to be_valid
    end

    it "is valid on the profile form with a major, class year, and T-shirt size" do
      expect(profile_user).to be_valid(:profile)
    end

    it "leaves the major and T-shirt size optional on the profile form" do
      expect(build_user).to be_valid(:profile)
    end

    it "limits the length of a major" do
      expect(profile_user(major: "K" * (User::MAJOR_MAX_LENGTH + 1))).not_to be_valid(:profile)
    end

    it "accepts every listed T-shirt size and nothing else" do
      User::TSHIRT_SIZES.each { |size| expect(profile_user(tshirt_size: size)).to be_valid(:profile) }
      expect(profile_user(tshirt_size: "m")).not_to be_valid(:profile)
    end

    it "tidies extra spaces in the major" do
      expect(profile_user(major: "  Allied   Health ").major).to eq("Allied Health")
    end

    it "survives a later Clerk sync" do
      user = profile_user(clerk_user_id: "user_profile", email: "profile@tamu.edu")
      user.save!

      synced = User.sync_from_clerk(email_verified: true, clerk_user_id: "user_profile", email: user.email, first_name: "Pat", last_name: nil)

      expect(synced).to have_attributes(major: "Kinesiology", class_year: Date.current.year + 1, tshirt_size: "M")
    end
  end

  it "builds a display name from first and last name" do
    expect(build_user(first_name: "Hudson", last_name: "Lee").display_name).to eq("Hudson Lee")
  end

  it "falls back to email when names are missing" do
    expect(build_user(first_name: nil, last_name: nil).display_name).to eq("member@example.com")
  end

  it "sums points from sessions the member attended" do
    create_current_term
    member = create_user
    officer = create_officer
    attended = Event.create!(title: "Meeting", starts_at: 2.days.ago, points: 2, created_by: officer)
    Event.create!(title: "Missed", starts_at: 1.day.ago, points: 5, created_by: officer)
    Attendance.create!(event: attended, user: member, recorded_by: officer)

    expect(member.points_earned).to eq(2)
  end

  describe "officers and points" do
    before { create_current_term }
    def attend(person, officer, points:, category: :general)
      event = Event.create!(title: "#{category} session", starts_at: 1.day.ago, points: points, category: category, created_by: officer)
      Attendance.create!(event: event, user: person, recorded_by: officer)
    end

    it "says members earn points and officers do not" do
      expect(build_user).to be_earns_points
      expect(build_user(role: :officer)).not_to be_earns_points
    end

    it "lists only members as earning points" do
      member = create_user
      officer = create_officer

      expect(User.earning_points).to include(member)
      expect(User.earning_points).not_to include(officer)
    end

    it "gives an officer no points for sessions they attended, while keeping the attendance" do
      officer = create_officer
      attend(officer, officer, points: 5)
      attend(officer, officer, points: 1, category: :professional)
      attend(officer, officer, points: 1, category: :social)

      expect(officer.attended_events.count).to eq(3)
      expect(officer.points_earned).to eq(0)
      expect(officer.points_by_category).to eq("general" => 0, "professional" => 0, "social" => 0)
      expect(officer.points_requirement_met?).to be(false)
    end

    it "gives a member the full points for the session an officer also attended" do
      officer = create_officer
      member = create_user
      event = Event.create!(title: "Shared session", starts_at: 1.day.ago, points: 4, created_by: officer)
      Attendance.create!(event: event, user: officer, recorded_by: officer)
      Attendance.create!(event: event, user: member, recorded_by: officer)

      expect(member.points_earned).to eq(4)
      expect(officer.points_earned).to eq(0)
    end

    it "follows the current role, so a promoted member stops earning from past sessions" do
      officer = create_officer
      member = create_user
      attend(member, officer, points: 3)

      expect { member.update!(role: :officer) }.to change { member.points_earned }.from(3).to(0)
      expect(member.attended_events.count).to eq(1)
    end
  end

  describe "#points_requirement_met?" do
    before { create_current_term }
    def attend(member, officer, points:, category: :general)
      event = Event.create!(title: "#{category} session", starts_at: 1.day.ago, points: points, category: category, created_by: officer)
      Attendance.create!(event: event, user: member, recorded_by: officer)
    end

    it "is met with 7 points including a professional and a social point" do
      member = create_user
      officer = create_officer
      attend(member, officer, points: 5)
      attend(member, officer, points: 1, category: :professional)
      attend(member, officer, points: 1, category: :social)

      expect(member.points_requirement_met?).to be(true)
      expect(member.missing_category_points).to eq("professional" => 0, "social" => 0)
    end

    it "lets professional and social points count toward the 7 total" do
      member = create_user
      officer = create_officer
      attend(member, officer, points: 4, category: :professional)
      attend(member, officer, points: 3, category: :social)

      expect(member.points_requirement_met?).to be(true)
    end

    it "is not met without a social point even with 7 points" do
      member = create_user
      officer = create_officer
      attend(member, officer, points: 6)
      attend(member, officer, points: 1, category: :professional)

      expect(member.points_requirement_met?).to be(false)
      expect(member.missing_category_points).to eq("professional" => 0, "social" => 1)
    end

    it "is not met with fewer than 7 points" do
      member = create_user
      officer = create_officer
      attend(member, officer, points: 1, category: :professional)
      attend(member, officer, points: 1, category: :social)

      expect(member.points_requirement_met?).to be(false)
    end

    it "is not met without a professional point even with 7 points" do
      member = create_user
      officer = create_officer
      attend(member, officer, points: 6)
      attend(member, officer, points: 1, category: :social)

      expect(member.points_requirement_met?).to be(false)
      expect(member.missing_category_points).to eq("professional" => 1, "social" => 0)
    end

    it "counts points in each category and leaves the others at zero" do
      member = create_user
      officer = create_officer
      attend(member, officer, points: 3, category: :social)

      expect(member.points_by_category).to eq("general" => 0, "professional" => 0, "social" => 3)
    end

    it "counts points in the given term only" do
      member = create_user
      officer = create_officer
      spring = create_term(name: "Spring-points", starts_on: Date.new(2026, 1, 13), ends_on: Date.new(2026, 5, 8))
      summer = create_term(name: "Summer-points", starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2026, 7, 31))
      spring_event = Event.create!(title: "Spring meeting", starts_at: Time.zone.parse("2026-03-02 18:00"), points: 5, created_by: officer)
      summer_event = Event.create!(title: "Summer clinic", starts_at: Time.zone.parse("2026-06-15 18:00"), points: 2, created_by: officer)
      Attendance.create!(event: spring_event, user: member, recorded_by: officer)
      Attendance.create!(event: summer_event, user: member, recorded_by: officer)

      expect(member.points_earned(summer)).to eq(2)
      expect(member.points_earned(spring)).to eq(5)
      expect(member.points_requirement_met?(summer)).to be(false)
    end
  end

  describe "point adjustments" do
    include ActiveSupport::Testing::TimeHelpers
    let(:term) { create_current_term }
    let(:officer) { create_officer }
    let(:member) { create_user }

    def attend(points:, category: :general, starts_at: 2.days.ago)
      event = Event.create!(title: "#{category} session", starts_at: starts_at, points: points, category: category, created_by: officer)
      Attendance.create!(event: event, user: member, recorded_by: officer)
    end

    def adjust(points:, category: :general, in_term: term)
      PointAdjustment.create!(user: member, term: in_term, recorded_by: officer, points: points, category: category, reason: "Correction")
    end

    # O14.1
    it "adds adjustments to session points, by category" do
      attend(points: 2, category: :professional)
      adjust(points: 3, category: :social)
      adjust(points: -1, category: :professional)

      expect(member.points_by_category(term)).to eq("general" => 0, "professional" => 1, "social" => 3)
      expect(member.points_earned(term)).to eq(4)
      expect(member.missing_category_points(term)).to eq("professional" => 0, "social" => 0)
    end

    # O14.4
    it "keeps adjustments to their own term" do
      past = create_term(name: "Past-adjust", starts_on: term.starts_on - 200.days, ends_on: term.starts_on - 100.days)
      adjust(points: 5, in_term: past)
      adjust(points: 1)

      expect(member.points_earned).to eq(1)
      expect(member.points_earned(past)).to eq(5)
      expect(member.points_earned(nil)).to eq(6)
    end

    # O14.3
    it "stops counting adjustments once a member becomes an officer" do
      adjust(points: 3)

      expect { member.update!(role: :officer) }.to change { member.points_earned(term) }.from(3).to(0)
      expect(member.point_adjustments.count).to eq(1)
    end

    # O14.1: points history
    it "lists check-ins and adjustments together, newest first" do
      checkin = attend(points: 2)
      adjustment = travel_to(1.minute.from_now) { adjust(points: 1) }
      past = create_term(name: "Past-history", starts_on: term.starts_on - 200.days, ends_on: term.starts_on - 100.days)
      old_checkin = attend(points: 4, starts_at: (past.starts_on + 1.day).in_time_zone)

      expect(member.points_history(term)).to eq([ adjustment, checkin ])
      expect(member.points_history(term, limit: 1)).to eq([ adjustment ])
      expect(member.points_history(nil)).to contain_exactly(adjustment, checkin, old_checkin)
    end

    # O14.1: totals on the member list and in the CSV report
    it "totals points per member and category for a term in one pass" do
      other = create_user
      attend(points: 2, category: :professional)
      adjust(points: 3, category: :professional)
      adjust(points: 1, category: :social)
      past = create_term(name: "Past-totals", starts_on: term.starts_on - 200.days, ends_on: term.starts_on - 100.days)
      adjust(points: 7, in_term: past)

      expect(User.category_points_by_user(term)).to eq([ member.id, "professional" ] => 5, [ member.id, "social" ] => 1)
      expect(User.category_points_by_user(nil)).to include([ member.id, "general" ] => 7)
      expect(User.category_points_by_user(term).keys.map(&:first)).not_to include(other.id)
    end
  end
end
