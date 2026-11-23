class CreatePointAdjustments < ActiveRecord::Migration[8.1]
  def change
    # O14.4: officer corrections to one member's points in one term, kept in the database.
    # Points are signed: negative subtracts.
    create_table :point_adjustments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.integer :points, null: false
      t.integer :category, null: false
      t.text :reason, null: false

      t.timestamps
    end
  end
end
