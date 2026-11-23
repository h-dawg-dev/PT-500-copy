# Society-wide configuration. Officers can switch the @tamu.edu requirement off,
# for example to test with personal accounts.
# The table is intentionally a singleton: the migration creates its first row.
class AppSetting < ApplicationRecord
     validates :require_tamu_email, inclusion: { in: [ true, false ] }
     # first_or_create! keeps old databases and test resets working even if the
     # seed row is ever removed by hand. Ordering by id keeps reads stable if a
     # duplicate row is ever created by mistake.
     def self.current
          order(:id).first_or_create!
     end

     def self.require_tamu_email?
          current.require_tamu_email?
     end

     def self.require_tamu_email=(value)
          current.update!(require_tamu_email: value)
     end
end
