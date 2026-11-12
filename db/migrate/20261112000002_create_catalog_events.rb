class CreateCatalogEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :catalog_events do |t|
      t.string :tid, null: false
      t.string :source, null: false, default: "billetto"
      t.string :external_id, null: false
      t.string :title, null: false
      t.text :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string :url
      t.string :image_url
      t.string :venue_name
      t.string :city
      t.string :country_code, limit: 2
      t.string :organiser_name
      t.integer :min_price_cents
      t.string :currency, limit: 3
      t.string :content_digest, null: false
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :last_synced_at, null: false
      t.timestamps
    end

    add_index :catalog_events, :tid, unique: true
    # Idempotent ingestion: one row per upstream event, enforced by the database.
    add_index :catalog_events, [ :source, :external_id ], unique: true
    # Listing upcoming events uses keyset pagination on (starts_at, id).
    add_index :catalog_events, [ :starts_at, :id ]

    add_check_constraint :catalog_events, "ends_at IS NULL OR ends_at >= starts_at", name: "catalog_events_ends_after_start"
    add_check_constraint :catalog_events, "min_price_cents IS NULL OR min_price_cents >= 0", name: "catalog_events_price_non_negative"
  end
end
