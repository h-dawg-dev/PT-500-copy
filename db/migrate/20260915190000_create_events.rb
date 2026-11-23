class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.string :location
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.integer :points, null: false, default: 0
      t.text :notes
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :events, :starts_at
  end
end
