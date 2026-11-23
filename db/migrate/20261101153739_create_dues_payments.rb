class CreateDuesPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :dues_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # One payment per member per term. A row means "paid"; a new term starts with no rows.
    add_index :dues_payments, %i[ user_id term_id ], unique: true
  end
end
