require "csv"

# Plain-text cells are escaped for spreadsheet use without changing stored data.
class OfficerCsvExport
     REPORTS = %w[events attendances members].freeze

     def initialize(report:, term:)
          @report = report
          @term = term
     end

     def generate
          raise ArgumentError, "Unknown CSV report" unless REPORTS.include?(@report)

          CSV.generate(row_sep: "\r\n", force_quotes: true) do |csv|
               send("write_#{@report}", csv)
          end
     end

  private

       def events
            @term ? Event.where(term_id: @term.id) : Event.all
       end

       def append(csv, values)
            csv << values.map { |value| safe_cell(value) }
       end

       def safe_cell(value)
            return value unless value.is_a?(String)

            value.match?(/\A[\s\uFEFF]*[=+\-@]/) || value.start_with?("\t", "\r", "\n") ? "'#{value}" : value
       end

       def timestamp(time)
            time&.in_time_zone&.iso8601
       end

       def write_events(csv)
            append(csv, [ "Event ID", "GetInvolved Reference", "Title", "Starts", "Ends", "Location", "Notes",
                          "Category", "Points", "Term", "Attendance Count", "RSVP Count", "Organization",
                          "GetInvolved Status", "Visibility", "Event Planner" ])
            events.includes(:term, :attendances, :rsvps).order(:starts_at, :id).each do |event|
                 append(csv, [ event.id, event.getinvolved_reference, event.title, timestamp(event.starts_at), timestamp(event.ends_at),
                               event.location, event.notes, event.category, event.points, event.term&.name, event.attendances.size,
                               event.rsvps.size, *event.getinvolved_data.values_at("Organization", "Status", "Visibility", "Event Planner") ])
            end
       end

       def write_attendances(csv)
            append(csv, [ "Attendance ID", "Event ID", "GetInvolved Reference", "Event", "Starts", "Term", "Category",
                          "Points", "User ID", "Name", "Email", "Role", "Recorded By", "Recorded At" ])
            Attendance.where(event_id: events.select(:id)).includes(:user, :recorded_by, event: :term).order(:id).each do |attendance|
                 event = attendance.event
                 append(csv, [ attendance.id, event.id, event.getinvolved_reference, event.title, timestamp(event.starts_at), event.term&.name,
                               event.category, attendance.points_awarded, attendance.user_id, attendance.user.display_name,
                               attendance.user.email, attendance.user.role, attendance.recorded_by&.display_name, timestamp(attendance.created_at) ])
            end
       end

       def write_members(csv)
            append(csv, [ "User ID", "Name", "Email", "Role", "Period", "Attendance Count", "Adjustment Points", "Points",
                          "General Points", "Professional Points", "Social Points", "Required Points",
                          "Required Professional Points", "Required Social Points", "Requirement Met" ])
            # Officers are outside the points system, so this report lists members only.
            # Their attendance is still in the attendance report.
            totals = User.category_points_by_user(@term)
            adjustments = PointAdjustment.for_period(@term).group(:user_id).sum(:points)
            counts = Attendance.where(event_id: events.select(:id)).group(:user_id).count
            required = @term&.required_points || User::REQUIRED_POINTS
            categories = @term&.required_category_points || User::REQUIRED_CATEGORY_POINTS
            User.earning_points.order(:last_name, :first_name, :email, :id).each do |user|
                 points = Event.categories.keys.index_with { |category| totals.fetch([ user.id, category ], 0) }
                 total = points.values.sum
                 met = total >= required && categories.all? { |category, minimum| points.fetch(category) >= minimum }
                 append(csv, [ user.id, user.display_name, user.email, user.role, @term&.name || "All time", counts.fetch(user.id, 0),
                               adjustments.fetch(user.id, 0), total, *points.values_at("general", "professional", "social"), required,
                               categories["professional"], categories["social"], met ])
            end
       end
end
