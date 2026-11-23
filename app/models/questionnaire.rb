# The new member intake form.
#
# Kept apart from QuestionnaireResponse so the first-time onboarding form and
# the "My information" pages share one question list, one answer filter, and
# one set of required fields.
#
# Each entry renders as its own card on the form, in order. To add a question, add a hash:
#   type: :choice needs options: { "stored_value" => "Label shown" }
#   type: :select needs the same options: and shows them in a dropdown; placeholder: is its blank entry
#   type: :short  is a one-line box; takes optional placeholder:, input: ("email"), autocomplete:, maxlength:
#   type: :text   is a multi-line box; takes optional placeholder: and rows:
#   type: :semester_year is a semester dropdown and a year dropdown, saved together as "Fall 2028"
# Any question can add required: true to block submitting without an answer.
module Questionnaire
     YES_NO = { "yes" => "Yes", "no" => "No" }.freeze

     # Answers that describe the account rather than the member's background.
     IDENTITY_KEYS = %w[ name email ].freeze

     QUESTIONS = [
       {
         key: :name,
         type: :short,
         prompt: "First & Last Name",
         placeholder: "First Last",
         autocomplete: "name",
         required: true
       },
       {
         key: :email,
         type: :short,
         prompt: "TAMU Email",
         input: "email",
         placeholder: "you@tamu.edu",
         autocomplete: "email",
         required: true
       },
       {
         key: :classification,
         type: :choice,
         prompt: "What is your classification?",
         options: {
           "freshman" => "Freshman",
           "sophomore" => "Sophomore",
           "junior" => "Junior",
           "senior" => "Senior",
           "grad_student" => "Graduate Student"
         }
       },
       {
         key: :expected_graduation,
         type: :semester_year,
         prompt: "When is your expected graduation date?",
         semesters: %w[ Spring Summer Fall ]
       },
       {
         key: :major,
         type: :short,
         prompt: "What is your major?",
         placeholder: "Kinesiology",
         maxlength: User::MAJOR_MAX_LENGTH
       },
       {
         key: :transfer_student,
         type: :choice,
         prompt: "Are you a transfer student?",
         options: YES_NO.merge("prefer_not_to_answer" => "Prefer not to answer")
       },
       {
         key: :first_generation,
         type: :choice,
         prompt: "Are you a first-generation college student?",
         options: YES_NO.merge("prefer_not_to_answer" => "Prefer not to answer")
       },
       {
         key: :tshirt_size,
         type: :select,
         prompt: "What is your T-shirt size?",
         placeholder: "Choose a size",
         options: User::TSHIRT_SIZES.index_by(&:itself)
       },
       {
         key: :email_opt_in,
         type: :choice,
         prompt: "Would you like to receive emails from us about opportunities and information?",
         options: YES_NO
       }
     ].freeze

     # Everything except the account identity (name and email).
     def self.detail_questions
          QUESTIONS.reject { |question| IDENTITY_KEYS.include?(question[:key].to_s) }
     end

     # Worked out on each call because QUESTIONS is frozen when the app boots.
     def self.graduation_years(today = Date.current)
          today.year..(today.year + 8)
     end

     # Keeps only answers to known questions, and only listed options for multiple choice.
     def self.filter_answers(raw, questions: QUESTIONS)
          questions.each_with_object({}) do |question, answers|
               key = question[:key].to_s
               value = question[:type] == :semester_year ? semester_year_answer(question, raw[key]) : raw[key].to_s.strip
               next if value.blank?
               next if question[:options] && !question[:options].key?(value)

               answers[key] = value
          end
     end

     # "Fall 2028", or nil unless both parts were picked from their lists.
     def self.semester_year_answer(question, raw)
          return unless raw.respond_to?(:key?)

          semester, year = raw["semester"], raw["year"]
          "#{semester} #{year}" if question[:semesters].include?(semester) && graduation_years.map(&:to_s).include?(year)
     end

     # What each form field holds for these answers, by field name, so the page can
     # tell when a member has changed something.
     def self.field_values(answers)
          QUESTIONS.each_with_object({}) do |question, fields|
               name = "questionnaire[#{question[:key]}]"
               value = answers[question[:key].to_s].to_s

               if question[:type] == :semester_year
                    semester, year = value.split
                    fields["#{name}[semester]"] = semester.to_s
                    fields["#{name}[year]"] = year.to_s
               else
                    fields[name] = question[:options].nil? || question[:options].key?(value) ? value : ""
               end
          end
     end

     def self.missing_required(answers, questions: QUESTIONS)
          questions.select { |question| question[:required] && answers[question[:key].to_s].blank? }
     end
end
