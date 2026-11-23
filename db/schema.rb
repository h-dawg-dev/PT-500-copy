# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_01_153739) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "require_tamu_email", default: true, null: false
    t.datetime "updated_at", null: false
  end

  create_table "attendances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "recorded_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id"], name: "index_attendances_on_event_id"
    t.index ["recorded_by_id"], name: "index_attendances_on_recorded_by_id"
    t.index ["user_id", "event_id"], name: "index_attendances_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_attendances_on_user_id"
  end

  create_table "dues_payments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "recorded_by_id"
    t.bigint "term_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["recorded_by_id"], name: "index_dues_payments_on_recorded_by_id"
    t.index ["term_id"], name: "index_dues_payments_on_term_id"
    t.index ["user_id", "term_id"], name: "index_dues_payments_on_user_id_and_term_id", unique: true
    t.index ["user_id"], name: "index_dues_payments_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "ends_at"
    t.jsonb "getinvolved_data", default: {}, null: false
    t.string "getinvolved_reference"
    t.string "location"
    t.text "notes"
    t.integer "points", default: 0, null: false
    t.datetime "starts_at", null: false
    t.bigint "term_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_events_on_category"
    t.index ["created_by_id"], name: "index_events_on_created_by_id"
    t.index ["getinvolved_reference"], name: "index_events_on_getinvolved_reference", unique: true
    t.index ["starts_at"], name: "index_events_on_starts_at"
    t.index ["term_id"], name: "index_events_on_term_id"
  end

  create_table "point_adjustments", force: :cascade do |t|
    t.integer "category", null: false
    t.datetime "created_at", null: false
    t.integer "points", null: false
    t.text "reason", null: false
    t.bigint "recorded_by_id"
    t.datetime "seen_at"
    t.bigint "term_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["recorded_by_id"], name: "index_point_adjustments_on_recorded_by_id"
    t.index ["term_id"], name: "index_point_adjustments_on_term_id"
    t.index ["user_id"], name: "index_point_adjustments_on_user_id"
  end

  create_table "questionnaire_responses", force: :cascade do |t|
    t.jsonb "answers", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.jsonb "questions", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["email"], name: "index_questionnaire_responses_on_email"
    t.index ["user_id"], name: "index_questionnaire_responses_on_user_id"
  end

  create_table "rsvps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id"], name: "index_rsvps_on_event_id"
    t.index ["user_id", "event_id"], name: "index_rsvps_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_rsvps_on_user_id"
  end

  create_table "terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "ends_on", null: false
    t.string "name", null: false
    t.integer "required_points", default: 7, null: false
    t.integer "required_professional_points", default: 1, null: false
    t.integer "required_social_points", default: 1, null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_terms_on_name", unique: true
    t.index ["starts_on"], name: "index_terms_on_starts_on"
  end

  create_table "users", force: :cascade do |t|
    t.integer "class_year"
    t.string "clerk_user_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "major"
    t.integer "role", default: 0, null: false
    t.string "tshirt_size"
    t.datetime "updated_at", null: false
    t.index ["clerk_user_id"], name: "index_users_on_clerk_user_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "attendances", "events"
  add_foreign_key "attendances", "users"
  add_foreign_key "attendances", "users", column: "recorded_by_id"
  add_foreign_key "dues_payments", "terms"
  add_foreign_key "dues_payments", "users"
  add_foreign_key "dues_payments", "users", column: "recorded_by_id"
  add_foreign_key "events", "terms"
  add_foreign_key "events", "users", column: "created_by_id"
  add_foreign_key "point_adjustments", "terms"
  add_foreign_key "point_adjustments", "users"
  add_foreign_key "point_adjustments", "users", column: "recorded_by_id"
  add_foreign_key "questionnaire_responses", "users"
  add_foreign_key "rsvps", "events"
  add_foreign_key "rsvps", "users"
end
