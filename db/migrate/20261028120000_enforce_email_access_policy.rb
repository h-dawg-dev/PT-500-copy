class EnforceEmailAccessPolicy < ActiveRecord::Migration[8.1]
  def up
    change_column_default :app_settings, :require_tamu_email, from: false, to: true
    execute "UPDATE app_settings SET require_tamu_email = TRUE"
  end

  def down
    change_column_default :app_settings, :require_tamu_email, from: true, to: false
  end
end
