class CreateAppSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :app_settings do |t|
      t.boolean :require_tamu_email, null: false, default: false
      t.timestamps
    end

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          INSERT INTO app_settings (require_tamu_email, created_at, updated_at)
          VALUES (FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end
  end
end
