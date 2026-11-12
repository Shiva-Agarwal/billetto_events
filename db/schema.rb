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

ActiveRecord::Schema[8.1].define(version: 2026_11_12_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "catalog_events", force: :cascade do |t|
    t.string "tid", null: false
    t.string "source", default: "billetto", null: false
    t.string "external_id", null: false
    t.string "title", null: false
    t.text "description"
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.string "url"
    t.string "image_url"
    t.string "venue_name"
    t.string "city"
    t.string "country_code", limit: 2
    t.string "organiser_name"
    t.integer "min_price_cents"
    t.string "currency", limit: 3
    t.string "content_digest", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "last_synced_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "external_id"], name: "index_catalog_events_on_source_and_external_id", unique: true
    t.index ["starts_at", "id"], name: "index_catalog_events_on_starts_at_and_id"
    t.index ["tid"], name: "index_catalog_events_on_tid", unique: true
    t.check_constraint "ends_at IS NULL OR ends_at >= starts_at", name: "catalog_events_ends_after_start"
    t.check_constraint "min_price_cents IS NULL OR min_price_cents >= 0", name: "catalog_events_price_non_negative"
  end

  create_table "event_store_events", force: :cascade do |t|
    t.uuid "event_id", null: false
    t.string "event_type", null: false
    t.jsonb "metadata"
    t.jsonb "data", null: false
    t.datetime "created_at", null: false
    t.datetime "valid_at"
    t.index ["created_at"], name: "index_event_store_events_on_created_at"
    t.index ["event_id"], name: "index_event_store_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_event_store_events_on_event_type"
    t.index ["valid_at"], name: "index_event_store_events_on_valid_at"
  end

  create_table "event_store_events_in_streams", force: :cascade do |t|
    t.string "stream", null: false
    t.integer "position"
    t.uuid "event_id", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_event_store_events_in_streams_on_created_at"
    t.index ["event_id"], name: "index_event_store_events_in_streams_on_event_id"
    t.index ["stream", "event_id"], name: "index_event_store_events_in_streams_on_stream_and_event_id", unique: true
    t.index ["stream", "position"], name: "index_event_store_events_in_streams_on_stream_and_position", unique: true
  end

  create_table "event_vote_tallies", force: :cascade do |t|
    t.string "event_tid", null: false
    t.integer "upvotes", default: 0, null: false
    t.integer "downvotes", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_tid"], name: "index_event_vote_tallies_on_event_tid", unique: true
  end

  create_table "identity_users", force: :cascade do |t|
    t.string "clerk_user_id", null: false
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.string "image_url"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["clerk_user_id"], name: "index_identity_users_on_clerk_user_id", unique: true
  end

  create_table "incoming_webhooks", force: :cascade do |t|
    t.string "service", null: false
    t.string "external_id", null: false
    t.string "event_type"
    t.jsonb "data", default: {}, null: false
    t.datetime "handled_at"
    t.boolean "handled"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["handled_at"], name: "index_incoming_webhooks_on_handled_at"
    t.index ["service", "external_id"], name: "index_incoming_webhooks_on_service_and_external_id", unique: true
  end

  create_table "processed_facts", force: :cascade do |t|
    t.string "handler", null: false
    t.uuid "event_id", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_processed_facts_on_created_at"
    t.index ["handler", "event_id"], name: "index_processed_facts_on_handler_and_event_id", unique: true
  end

  create_table "voting_votes", force: :cascade do |t|
    t.string "event_tid", null: false
    t.string "user_id", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_tid", "user_id"], name: "index_voting_votes_on_event_tid_and_user_id", unique: true
    t.index ["user_id"], name: "index_voting_votes_on_user_id"
    t.check_constraint "value IS NULL OR (value::text = ANY (ARRAY['up'::character varying, 'down'::character varying]::text[]))", name: "voting_votes_value_valid"
  end

  add_foreign_key "event_store_events_in_streams", "event_store_events", column: "event_id", primary_key: "event_id"
end
