require "rails_helper"
require "csv"

RSpec.describe AttendanceImport do
     let(:officer) { create_officer }
  let(:event) do
       Event.create!(title: "General Meeting", starts_at: Time.zone.local(2026, 10, 6, 21),
                     ends_at: Time.zone.local(2026, 10, 6, 22), points: 1, category: :general, created_by: officer)
  end
  let!(:ada) { create_user(email: "ada@example.com") }
  let!(:grace) { create_user(email: "grace@example.com") }

  # Same columns as a GetInvolved attendance export. The rows are anonymous.
  def attendance_headers
       [ "Checked In", "Entries", "# in Party", "First Name", "Last Name", "Email", "Card Issuer" ]
  end

  def attendee_row(email)
       [ "10/06/2026 10:33 PM", "1", "1", "Test", "Person", email, nil ]
  end

  def upload(emails, headers: attendance_headers, format: :csv)
       rows = emails.map { |email| attendee_row(email) }
    if format == :xlsx
         getinvolved_workbook(rows, headers: headers)
    else
         "﻿#{CSV.generate { |csv| csv << headers; rows.each { |row| csv << row } }}"
    end
  end

  def import(emails = [ ada.email, grace.email ], **options)
       described_class.new(file: StringIO.new(upload(emails, **options)), event: event, officer: officer).call
  end

  it "marks everyone listed as present, recorded by the officer" do
       result = import
    expect(result).to be_success
    expect(result.created_count).to eq(2)
    expect(result.skipped_count).to eq(0)
    expect(event.attendances.map(&:user)).to contain_exactly(ada, grace)
    expect(event.attendances.map(&:recorded_by).uniq).to eq([ officer ])
  end

  it "reads native Excel (.xlsx) exports with blank cells" do
       result = import(format: :xlsx)
    expect(result).to be_success
    expect(result.created_count).to eq(2)
    expect(event.attendances.map(&:user)).to contain_exactly(ada, grace)
  end

  it "skips people who are already present and keeps who recorded them" do
       earlier_officer = create_officer
    existing = Attendance.create!(event: event, user: ada, recorded_by: earlier_officer)
    result = import
    expect(result).to be_success
    expect(result.created_count).to eq(1)
    expect(result.skipped_count).to eq(1)
    expect(existing.reload.recorded_by).to eq(earlier_officer)
  end

  it "is safe to import twice" do
       import
    result = nil
    expect { result = import }.not_to change(Attendance, :count)
    expect(result.created_count).to eq(0)
    expect(result.skipped_count).to eq(2)
  end

  it "matches emails regardless of case and surrounding spaces" do
       mixed = create_user(email: "Mixed.Case@Example.com")
    result = import([ " ADA@example.com ", "mixed.case@example.com" ])
    expect(result).to be_success
    expect(result.created_count).to eq(2)
    expect(event.attendances.map(&:user)).to contain_exactly(ada, mixed)
  end

  it "rejects the whole file when an email has no member" do
       result = nil
    expect { result = import([ ada.email, "nobody@example.com" ]) }.not_to change(Attendance, :count)
    expect(result).not_to be_success
    expect(result.errors).to eq([ "Row 3: No member has the email nobody@example.com." ])
  end

  it "lists at most 20 unknown emails and counts the rest" do
       result = import((1..22).map { |n| "nobody#{n}@example.com" })
    expect(result.errors.size).to eq(21)
    expect(result.errors.first).to eq("Row 2: No member has the email nobody1@example.com.")
    expect(result.errors.last).to eq("2 more emails have no matching member.")
  end

  it "rejects the same email twice in one file, ignoring case" do
       result = nil
    expect { result = import([ ada.email, ada.email.upcase ]) }.not_to change(Attendance, :count)
    expect(result.errors).to eq([ "Row 3: Email ada@example.com appears more than once." ])
  end

  it "rejects missing and invalid emails" do
       expect(import([ "" ]).errors).to eq([ "Row 2: Email is missing." ])
    expect(import([ "not-an-email" ]).errors).to eq([ "Row 2: Email not-an-email is not a valid address." ])
  end

  it "rejects missing or repeated column headers" do
       expect(import(headers: attendance_headers - [ "Email" ]).errors).to eq([ "Missing columns: Email." ])
    expect(import(headers: attendance_headers + [ "Email" ]).errors).to eq([ "Column headers must not be repeated." ])
  end

  it "rejects a file with only a header row" do
       expect(import([]).errors).to eq([ "The file has no attendance rows." ])
  end

  it "reports unreadable, empty, non-UTF-8, forged and oversized uploads without writing attendance" do
       files = [ StringIO.new(%(Email\n"unterminated)), StringIO.new(""), StringIO.new("\xFF".b), StringIO.new("PKbroken"),
                 StringIO.new("x" * (described_class::MAX_BYTES + 1)), "forged upload", nil ]
    files.each do |file|
         result = described_class.new(file: file, event: event, officer: officer).call
      expect(result).not_to be_success
    end
    expect(Attendance.count).to eq(0)
  end

  it "limits the row count before saving anything" do
       stub_const("AttendanceImport::MAX_ROWS", 2)
    result = nil
    expect { result = import([ ada.email, grace.email, "third@example.com" ]) }.not_to change(Attendance, :count)
    expect(result.errors.join).to include("at most 2")
  end

  it "rolls back earlier saves if a record appears while importing" do
       allow(Attendance).to receive(:create!).and_wrap_original do |original, **attributes|
            raise ActiveRecord::RecordNotUnique if attributes[:user] == grace

         original.call(**attributes)
       end
    result = nil
    expect { result = import }.not_to change(Attendance, :count)
    expect(result).not_to be_success
    expect(result.errors.join).to include("changed while importing")
  end
end
