class CreateIdentityUsersAndIncomingWebhooks < ActiveRecord::Migration[8.0]
  def change
    # Local projection of Clerk users (kept in sync via Clerk webhooks).
    create_table :identity_users do |t|
      t.string :clerk_user_id, null: false
      t.string :email
      t.string :first_name
      t.string :last_name
      t.string :image_url
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :identity_users, :clerk_user_id, unique: true

    # Audit log + async processing queue for incoming webhooks (Developer's Guide pattern).
    create_table :incoming_webhooks do |t|
      t.string :service, null: false
      t.string :external_id, null: false # provider delivery id (svix-id) -> dedupes retries
      t.string :event_type
      t.jsonb :data, null: false, default: {}
      t.datetime :handled_at
      t.boolean :handled
      t.text :last_error
      t.timestamps
    end
    add_index :incoming_webhooks, [ :service, :external_id ], unique: true
    add_index :incoming_webhooks, :handled_at
  end
end
