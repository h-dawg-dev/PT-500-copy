namespace :users do
     desc "Reset one account for a fresh demo (dry run unless APPLY=1; OFFICER=1 keeps or grants admin)"
     task :reset_for_demo, [ :email ] => :environment do |_task, args|
          email = args[:email].to_s.strip.downcase
          abort "Usage: [APPLY=1] [OFFICER=1] bin/rails 'users:reset_for_demo[person@tamu.edu]'" if email.blank?

          user = User.find_by(email: email)
          abort "No user with email #{email}." unless user

          reset = DemoAccountReset.new(user, officer: ENV["OFFICER"] == "1")
          puts "User ##{user.id}: #{user.display_name} <#{user.email}>, role=#{user.role}"
          reset.summary.each { |name, value| puts "  #{name}: #{value.inspect}" }

          unless ENV["APPLY"] == "1"
               puts "Dry run, nothing changed. Add APPLY=1 to reset."
               next
          end

          user = reset.call
          puts "Reset done. role=#{user.role}, questionnaire_completed?=#{user.questionnaire_completed?}"
     end
end
