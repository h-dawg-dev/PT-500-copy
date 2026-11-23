class CreateTermsAndRsvps < ActiveRecord::Migration[8.1]
  def up
    create_table :terms do |t|
      t.string :name, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :required_points, null: false, default: 7
      t.integer :required_professional_points, null: false, default: 1
      t.integer :required_social_points, null: false, default: 1

      t.timestamps
    end

    add_index :terms, :name, unique: true
    add_index :terms, :starts_on

    add_reference :events, :term, foreign_key: true

    create_table :rsvps do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true

      t.timestamps
    end

    add_index :rsvps, [ :user_id, :event_id ], unique: true

    now = Time.current
    insert_all_terms(now)

    execute(<<~SQL.squish)
      UPDATE events
      SET term_id = terms.id
      FROM terms
      WHERE events.starts_at::date BETWEEN terms.starts_on AND terms.ends_on
    SQL

    drop_table :playing_with_neon if table_exists?(:playing_with_neon)
  end

  def down
    create_table :playing_with_neon, id: :serial do |t|
      t.text :name, null: false
      t.float :value, limit: 24
    end

    drop_table :rsvps
    remove_reference :events, :term, foreign_key: true
    drop_table :terms
  end

  private

  def insert_all_terms(now)
    rows = [
      [ "Spring 2026", "2026-01-13", "2026-05-08" ],
      [ "Fall 2026", "2026-08-17", "2026-12-18" ],
      [ "Spring 2027", "2027-01-12", "2027-05-14" ]
    ]

    rows.each do |name, starts_on, ends_on|
      execute(<<~SQL.squish)
        INSERT INTO terms (name, starts_on, ends_on, required_points, required_professional_points, required_social_points, created_at, updated_at)
        VALUES (#{connection.quote(name)}, #{connection.quote(starts_on)}, #{connection.quote(ends_on)}, 7, 1, 1, #{connection.quote(now)}, #{connection.quote(now)})
      SQL
    end
  end
end
