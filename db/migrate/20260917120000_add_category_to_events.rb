class AddCategoryToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :category, :integer, null: false, default: 0
    add_index :events, :category
  end
end
