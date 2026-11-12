class CreateReadModelTables < ActiveRecord::Migration[8.0]
  def change
    # Denormalized vote counters per event, projected asynchronously from voting facts.
    create_table :event_vote_tallies do |t|
      t.string :event_tid, null: false
      t.integer :upvotes, null: false, default: 0
      t.integer :downvotes, null: false, default: 0
      t.timestamps
    end
    add_index :event_vote_tallies, :event_tid, unique: true

    # Idempotency ledger for at-least-once async handlers: a fact is applied to a projection
    # at most once per handler. Safe to prune entries older than the job retry window.
    create_table :processed_facts do |t|
      t.string :handler, null: false
      t.uuid :event_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :processed_facts, [ :handler, :event_id ], unique: true
    add_index :processed_facts, :created_at
  end
end
