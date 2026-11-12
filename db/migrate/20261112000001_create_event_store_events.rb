# Rails Event Store schema (PostgreSQL / jsonb variant), equivalent to
# `rails generate rails_event_store_active_record:migration --data-type=jsonb`.
class CreateEventStoreEvents < ActiveRecord::Migration[8.0]
  def change
    create_table(:event_store_events, id: :bigserial, force: false) do |t|
      t.uuid :event_id, null: false
      t.string :event_type, null: false
      t.jsonb :metadata
      t.jsonb :data, null: false
      t.datetime :created_at, null: false, precision: 6
      t.datetime :valid_at, null: true, precision: 6
    end
    add_index :event_store_events, :event_id, unique: true
    add_index :event_store_events, :created_at
    add_index :event_store_events, :valid_at
    add_index :event_store_events, :event_type

    create_table(:event_store_events_in_streams, id: :bigserial, force: false) do |t|
      t.string :stream, null: false
      t.integer :position, null: true
      t.uuid :event_id, null: false
      t.datetime :created_at, null: false, precision: 6
    end
    add_index :event_store_events_in_streams, [ :stream, :position ], unique: true
    add_index :event_store_events_in_streams, [ :created_at ]
    add_index :event_store_events_in_streams, [ :stream, :event_id ], unique: true
    add_index :event_store_events_in_streams, [ :event_id ]

    add_foreign_key :event_store_events_in_streams, :event_store_events, column: :event_id, primary_key: :event_id
  end
end
