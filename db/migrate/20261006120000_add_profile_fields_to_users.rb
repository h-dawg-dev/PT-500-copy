class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Members fill these in themselves from the dashboard, so existing accounts start empty.
    add_column :users, :major, :string
    add_column :users, :class_year, :integer
    add_column :users, :tshirt_size, :string
  end
end
