require "csv"
require "set"
require "roo"
require "uri"

# Records attendance for one event from a GetInvolved attendance export.
# Members are matched by email. Existing attendance is never changed.
class AttendanceImport
     REQUIRED_HEADERS = %w[Email].freeze
     MAX_BYTES = 2.megabytes
     MAX_EXPANDED_BYTES = 20.megabytes
     MAX_ROWS = 2000
     MAX_ERRORS = 20
     Result = Data.define(:created_count, :skipped_count, :errors) do
          def success?
               errors.empty?
          end
     end

     def initialize(file:, event:, officer:)
          @file = file
          @event = event
          @officer = officer
          @errors = []
          @emails = {} # normalized email => row number, in file order
     end

     def call
          return failure("Choose the GetInvolved Excel (.xlsx) export or a CSV UTF-8 file.") unless @file.respond_to?(:read)

          content = @file.read(MAX_BYTES + 1).to_s.dup
          return failure("The file must be no larger than 2 MB.") if content.bytesize > MAX_BYTES

          if content.b.start_with?("PK".b) || (@file.respond_to?(:original_filename) && File.extname(@file.original_filename.to_s).downcase == ".xlsx")
               parse_workbook(content)
          else
               content.force_encoding(Encoding::UTF_8)
               return failure("Upload the Excel (.xlsx) export or save the file as CSV UTF-8.") unless content.valid_encoding?

               parse_rows(CSV.new(content.delete_prefix("\uFEFF"), skip_blanks: true).each)
          end
          return result(0, 0) if @errors.any?

          persist
        rescue CSV::MalformedCSVError, ArgumentError, Zip::Error, Roo::Error, Nokogiri::XML::SyntaxError, IOError
             failure("The file could not be read. Upload a valid Excel (.xlsx) export or CSV UTF-8 with the original column headers.")
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
             failure("No attendance was imported. A record changed while importing; check the file and try again.")
     end

  private

       def parse_workbook(content)
            Zip::File.open_buffer(content) do |archive|
                 return failure("The Excel workbook expands beyond the 20 MB limit.") if archive.sum(&:size) > MAX_EXPANDED_BYTES
                 return failure("The file is not an Excel (.xlsx) workbook.") unless archive.find_entry("xl/workbook.xml") && archive.find_entry("xl/_rels/workbook.xml.rels")
            end
            workbook = Roo::Excelx.new(StringIO.new(content), no_hyperlinks: true)
            return failure("Use a workbook with one attendance worksheet.") unless workbook.sheets.size == 1

            rows = Enumerator.new do |output|
                 workbook.each_row_streaming(pad_cells: true) do |cells|
                      output << cells.map { |cell| cell&.value }
                 end
            end
            parse_rows(rows)
          ensure
               workbook&.close
       end

       def parse_rows(rows)
            headers = rows.next
            return failure("The file is empty or has no column headers.") unless headers.is_a?(Array)

            normalized = headers.map { |header| header.to_s.strip }
            missing = REQUIRED_HEADERS - normalized
            return failure("Missing columns: #{missing.join(', ')}.") if missing.any?
            return failure("Column headers must not be repeated.") if normalized.uniq.size != normalized.size
            row_number = 1
            # Continue the enumerator after its header without rewinding it.
            loop do
                 row = rows.next
                 row_number += 1
                 return failure("Import at most #{MAX_ROWS} attendees at a time.") if row_number > MAX_ROWS + 1

                 parse_row(row, normalized, row_number)
                 break if @errors.size >= MAX_ERRORS
            end
            failure("The file has no attendance rows.") if @emails.empty? && @errors.empty?
          rescue StopIteration
               failure("The file is empty or has no column headers.")
       end

       def parse_row(row, headers, number)
            return if row.all?(&:blank?)
            return row_error(number, "has more values than column headers") if row.size > headers.size

            email = headers.zip(row).to_h["Email"].to_s.strip.downcase
            return row_error(number, "Email is missing") if email.blank?
            return row_error(number, "Email #{email} is not a valid address") unless email.match?(URI::MailTo::EMAIL_REGEXP)
            return row_error(number, "Email #{email} appears more than once") if @emails.key?(email)

            @emails[email] = number
       end

       def persist
            users = User.where("LOWER(email) IN (?)", @emails.keys).index_by { |user| user.email.downcase }
            unknown = @emails.keys - users.keys
            return unknown_members(unknown) if unknown.any?

            already_recorded = Attendance.where(event_id: @event.id, user_id: users.values.map(&:id)).pluck(:user_id).to_set
            created = 0
            skipped = 0
            Attendance.transaction do
                 @emails.each_key do |email|
                      user = users.fetch(email)
                      if already_recorded.include?(user.id)
                           skipped += 1
                      else
                           Attendance.create!(event: @event, user: user, recorded_by: @officer)
                           created += 1
                      end
                 end
            end
            result(created, skipped)
       end

       def unknown_members(emails)
            emails.first(MAX_ERRORS).each { |email| row_error(@emails[email], "No member has the email #{email}") }
            @errors << "#{emails.size - MAX_ERRORS} more emails have no matching member." if emails.size > MAX_ERRORS
            result(0, 0)
       end

       def row_error(number, message)
            @errors << "Row #{number}: #{message}."
       end

       def failure(message)
            @errors << message
            result(0, 0)
       end

       def result(created, skipped)
            Result.new(created_count: created, skipped_count: skipped, errors: @errors)
       end
end
