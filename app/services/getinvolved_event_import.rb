require "csv"
require "cgi"
require "set"
require "roo"

# Imports event definitions only. Existing references never overwrite local credit.
class GetinvolvedEventImport
     HEADERS = [ "Reference", "Type", "Title", "Organization", "Starts", "Ends", "Status", "Location",
                 "Location Detail", "Marketing Blurb", "Visibility", "Event Planner" ].freeze
     REQUIRED_HEADERS = %w[Reference Type Title Starts Ends].freeze
     MAX_BYTES = 2.megabytes
     MAX_EXPANDED_BYTES = 20.megabytes
     MAX_ROWS = 2000
     MAX_ERRORS = 20
     Result = Data.define(:created_count, :skipped_count, :errors) do
          def success?
               errors.empty?
          end
     end

     def initialize(file:, officer:)
          @file = file
          @officer = officer
          @errors = []
          @events = []
          @references = Set.new
          @skipped_count = 0
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
             failure("No events were imported. An event changed while importing; check the file and try again.")
     end

  private

       def parse_workbook(content)
            Zip::File.open_buffer(content) do |archive|
                 return failure("The Excel workbook expands beyond the 20 MB limit.") if archive.sum(&:size) > MAX_EXPANDED_BYTES
                 return failure("The file is not an Excel (.xlsx) workbook.") unless archive.find_entry("xl/workbook.xml") && archive.find_entry("xl/_rels/workbook.xml.rels")
            end
            workbook = Roo::Excelx.new(StringIO.new(content), no_hyperlinks: true)
            return failure("Use a workbook with one event worksheet.") unless workbook.sheets.size == 1

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
                 return failure("Import at most #{MAX_ROWS} events at a time.") if row_number > MAX_ROWS + 1

                 parse_row(row, normalized, row_number)
                 break if @errors.size >= MAX_ERRORS
            end
            failure("The file has no event rows.") if row_number == 1 && @errors.empty?
          rescue StopIteration
               failure("The file is empty or has no column headers.")
       end

       def parse_row(row, headers, number)
            return if row.all?(&:blank?)
            return row_error(number, "has more values than column headers") if row.size > headers.size

            data = headers.zip(row).to_h.transform_values do |value|
                 value.is_a?(Time) || value.is_a?(DateTime) ? value.strftime("%b %d, %Y %I:%M %p") : value.to_s.strip
            end
            reference = data["Reference"]
            return row_error(number, "Reference must look like EVN-26994") unless reference.match?(/\AEVN-\d+\z/)
            return row_error(number, "Reference #{reference} appears more than once") unless @references.add?(reference)
            return row_error(number, "Type must be Event") unless data["Type"].casecmp?("Event")
            if Event.exists?(getinvolved_reference: reference)
                 @skipped_count += 1
                 return
            end

            event = build_event(data)
            if event.valid?
                 @events << event
            else
                 row_error(number, event.errors.full_messages.to_sentence)
            end
          rescue ArgumentError
               row_error(number, "Starts and Ends must use a GetInvolved date such as Sep 22, 2026 7:00 pm")
       end

       def build_event(data)
            Event.new(
              title: CGI.unescapeHTML(data.fetch("Title")),
              starts_at: parse_time(data.fetch("Starts")),
              ends_at: parse_time(data.fetch("Ends")),
              location: [ data["Location"], data["Location Detail"] ].reject(&:blank?).map { |part| CGI.unescapeHTML(part) }.uniq.join(" - "),
              notes: CGI.unescapeHTML(data["Marketing Blurb"].to_s),
              points: 1, category: :general, created_by: @officer,
              getinvolved_reference: data.fetch("Reference"),
              getinvolved_data: data.slice(*HEADERS)
            )
       end

       def parse_time(value)
            raise ArgumentError unless value.match?(/\A[A-Za-z]{3} \d{1,2}, \d{4} \d{1,2}:\d{2} [ap]m\z/i)

            parsed = DateTime.strptime(value, "%b %d, %Y %I:%M %p")
            Time.zone.local(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute)
       end

       def persist
            created = 0
            skipped = @skipped_count
            # Recheck for references created after parsing the file.
            Event.transaction do
                 @events.each do |event|
                      if Event.exists?(getinvolved_reference: event.getinvolved_reference)
                           skipped += 1
                      else
                           event.save!
                           created += 1
                      end
                 end
            end
            result(created, skipped)
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
