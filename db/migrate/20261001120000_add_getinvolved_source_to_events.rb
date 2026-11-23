class AddGetinvolvedSourceToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :getinvolved_reference, :string
    add_column :events, :getinvolved_data, :jsonb, default: {}, null: false
    add_index :events, :getinvolved_reference, unique: true
  end
end
