class QuestionnaireDashboard
     attr_reader :responses, :total_people, :filters

     def initialize(scope: QuestionnaireResponse.all, filters: {})
          @filters = normalize_filters(filters.to_h.stringify_keys)
          submissions = scope.includes(:user).order(created_at: :desc, id: :desc).to_a
          emails = submissions.select { |submission| submission.user_id.nil? }.map(&:email).uniq
          account_ids = emails.empty? ? {} : User.where(email: emails).pluck(:email, :id).to_h
          # Match the app's latest-response rule, including unclaimed legacy rows.
          latest = submissions.uniq do |submission|
               account_id = submission.user_id || account_ids[submission.email]
               account_id ? [ :user, account_id ] : [ :email, submission.email ]
          end
          @total_people = latest.size
          @responses = sort(latest.select { |submission| matches?(submission) })
     end

     def email_opt_ins
          responses.count { |submission| submission.answers["email_opt_in"] == "yes" }
     end

     def recent_updates
          responses.count { |submission| submission.updated_at >= 30.days.ago }
     end

     def unlinked
          responses.count { |submission| submission.user_id.nil? }
     end

     def percentage(count)
          responses.empty? ? 0 : (100.0 * count / responses.size).round
     end

     def distribution(key)
          options = question(key).fetch(:options)
          counts = responses.map { |submission| submission.answers[key].to_s.strip }.tally
          rows = options.map { |value, label| { label: label, count: counts.fetch(value, 0), muted: value == "prefer_not_to_answer" } }
          rows << { label: "Not answered", count: counts.fetch("", 0), muted: true }
          other = counts.reject { |value, _| value.blank? || options.key?(value) }.values.sum
          rows << { label: "Other / previous format", count: other, muted: true } if other.positive?
          rows.map { |row| row.merge(percentage: percentage(row[:count])) }
     end

     def name(submission)
          (submission.user&.display_name || submission.answers["name"].presence || "Name not provided").to_s
     end

     private

          def question(key)
               Questionnaire.detail_questions.find { |entry| entry[:key].to_s == key }
          end

          def normalize_filters(raw)
               result = { "q" => raw["q"].to_s.strip.first(200) }
               %w[classification email_opt_in].each do |key|
                    allowed = question(key).fetch(:options).keys + %w[unanswered other]
                    result[key] = allowed.include?(raw[key]) ? raw[key] : ""
               end
               result["link_status"] = %w[linked unlinked].include?(raw["link_status"]) ? raw["link_status"] : ""
               result["sort"] = %w[updated newest name].include?(raw["sort"]) ? raw["sort"] : "updated"
               result
          end

          def matches?(submission)
               query = filters["q"].downcase
               fields = [ name(submission), submission.email, submission.user&.email ]
               return false if query.present? && fields.compact.none? { |value| value.downcase.include?(query) }
               return false if filters["link_status"] == "linked" && submission.user_id.nil?
               return false if filters["link_status"] == "unlinked" && submission.user_id.present?

               %w[classification email_opt_in].all? do |key|
                    filter = filters[key]
                    value = submission.answers[key].to_s.strip
                    if filter.blank?
                         true
                    elsif filter == "unanswered"
                         value.blank?
                    elsif filter == "other"
                         value.present? && !question(key).fetch(:options).key?(value)
                    else
                         value == filter
                    end
               end
          end

          def sort(submissions)
               case filters["sort"]
               when "name"
                    submissions.sort_by { |submission| [ name(submission).downcase, submission.id ] }
               when "newest"
                    submissions.sort_by { |submission| [ -submission.created_at.to_f, -submission.id ] }
               else
                    submissions.sort_by { |submission| [ -submission.updated_at.to_f, -submission.id ] }
               end
          end
end
