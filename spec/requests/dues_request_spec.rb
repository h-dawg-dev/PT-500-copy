require "rails_helper"

RSpec.describe "Dues", type: :request do
     let(:officer) { create_officer }
  let!(:term) { create_current_term }
  let(:member) { create_user }
  let(:other_member) { create_user }

  # Every officer check goes through current_user, so signing in only needs that one method.
  def sign_in_as(user)
       allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  def record_dues(target = member, term_id: term.id)
       post officer_member_dues_payment_path(target), params: { expected_term_id: term_id }
  end

  def undo_dues(target = member, term_id: term.id)
       delete officer_member_dues_payment_path(target), params: { expected_term_id: term_id }
  end

  context "when signed in as an officer" do
       before { sign_in_as(officer) }

    it "records the member's dues for the current term and redirects back to their record" do
         expect { record_dues }.to change(DuesPayment, :count).by(1)
      payment = DuesPayment.last
      expect([ payment.user, payment.term, payment.recorded_by ]).to eq([ member, term, officer ])
      expect(response).to redirect_to(officer_member_path(member))
      expect(flash[:notice]).to include("marked as having paid #{term.name} dues")
      expect(member.dues_paid?(term)).to be(true)
    end

    it "does not record the same payment twice" do
         record_dues
      expect { record_dues }.not_to change(DuesPayment, :count)
      expect(response).to redirect_to(officer_member_path(member))
    end

    it "changes only that member's dues, never points, attendance or anyone else" do
         event = Event.create!(title: "General Meeting", starts_at: Time.zone.local(2026, 10, 6, 21),
                               ends_at: Time.zone.local(2026, 10, 6, 22), points: 1, category: :general,
                               term: term, created_by: officer)
      Attendance.create!(event: event, user: member, recorded_by: officer)
      points_before = member.points_earned(term)

      expect { record_dues }.not_to change { [ Attendance.count, Event.count, User.count ] }
      expect(member.reload.points_earned(term)).to eq(points_before)
      expect(other_member.dues_paid?(term)).to be(false)
    end

    it "undoes only that member's payment for the current term" do
         old_term = create_term(starts_on: Date.current - 300.days, ends_on: Date.current - 200.days)
      DuesPayment.create!(user: member, term: term)
      DuesPayment.create!(user: member, term: old_term)
      DuesPayment.create!(user: other_member, term: term)

      expect { undo_dues }.to change(DuesPayment, :count).by(-1)
      expect(response).to redirect_to(officer_member_path(member))
      expect(member.dues_paid?(term)).to be(false)
      expect(member.dues_paid?(old_term)).to be(true)
      expect(other_member.dues_paid?(term)).to be(true)
    end

    it "refuses to record dues for another officer" do
         other_officer = create_officer
      expect { record_dues(other_officer) }.not_to change(DuesPayment, :count)
      expect(response).to redirect_to(officer_member_path(other_officer))
      expect(flash[:alert]).to include("does not pay dues")
    end

    it "changes nothing when the page was for a different term" do
         expect { record_dues(term_id: term.id + 1) }.not_to change(DuesPayment, :count)
      expect(flash[:alert]).to include("semester changed")
    end

    it "changes nothing when no term covers today" do
         Term.delete_all
      expect { record_dues(term_id: 1) }.not_to change(DuesPayment, :count)
      expect(flash[:alert]).to include("no semester is active")
    end

    it "shows each state on the member's record" do
         get officer_member_path(member)
      expect(response.body).to include("Mark dues paid")
      expect(response.body).to include("Dues not paid yet for #{term.name}")

      DuesPayment.create!(user: member, term: term)
      get officer_member_path(member)
      expect(response.body).to include("Dues paid for #{term.name}")
      expect(response.body).to include("Undo dues payment")

      get officer_member_path(create_officer)
      expect(response.body).to include("Officers do not pay dues.")
      expect(response.body).not_to include("Mark dues paid")
    end
  end

  context "when signed in as a regular member" do
       before { sign_in_as(member) }

    it "cannot record their own or anyone else's dues" do
         expect { record_dues(member) }.not_to change(DuesPayment, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("That area is for officers.")

      expect { record_dues(other_member) }.not_to change(DuesPayment, :count)
      expect(response).to redirect_to(root_path)
    end

    it "cannot undo a payment" do
         DuesPayment.create!(user: member, term: term)
      expect { undo_dues(member) }.not_to change(DuesPayment, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  context "when signed out" do
       before { sign_in_as(nil) }

    it "is asked to sign in and changes nothing" do
         expect { record_dues }.not_to change(DuesPayment, :count)
      expect(flash[:alert]).to eq("Please sign in.")
    end
  end

  # These render the real pages, so they also check the layout still loads for each kind of user.
  describe "member home page" do
       it "shows unpaid, then paid, as the record changes" do
            sign_in_as(member)
         get root_path
         expect(response.body).to include("Your dues are not paid yet for #{term.name}")

         DuesPayment.create!(user: member, term: term)
         get root_path
         expect(response.body).to include("Your dues are paid for #{term.name}")
       end

    it "shows nothing about dues to an officer" do
         sign_in_as(officer)
      get root_path
      expect(response.body).not_to include("Your dues are")
    end
  end

  describe "Dues navigation link" do
       def with_dues_url(url)
            allow(ENV).to receive(:[]).and_call_original
         allow(ENV).to receive(:[]).with("DUES_PAYMENT_URL").and_return(url)
       end

    it "links members to the configured address in a new tab" do
         with_dues_url("https://pay.example.com/dues")
      sign_in_as(member)
      get root_path
      expect(response.body).to include('href="https://pay.example.com/dues"')
      expect(response.body).to include("noopener noreferrer")
    end

    it "is not shown to officers" do
         with_dues_url("https://pay.example.com/dues")
      sign_in_as(officer)
      get root_path
      expect(response.body).not_to include("pay.example.com")
    end

    it "is hidden when no address is set or the address is not https" do
         sign_in_as(member)
      [ nil, "", "http://pay.example.com/dues" ].each do |url|
           with_dues_url(url)
        get root_path
        expect(response.body).not_to include("pay.example.com")
      end
    end
  end
end
