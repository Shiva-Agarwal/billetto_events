# Write model of the Voting module: the *current* vote of a user for an event.
# The full history lives in Rails Event Store (EventUpvoted / EventDownvoted / VoteWithdrawn).
class CreateVotingVotes < ActiveRecord::Migration[8.0]
  def change
    create_table :voting_votes do |t|
      t.string :event_tid, null: false
      t.string :user_id, null: false
      t.string :value # "up" | "down" | NULL (withdrawn)
      t.timestamps
    end

    # One ballot per user per event; also the row we lock to serialize concurrent votes.
    add_index :voting_votes, [ :event_tid, :user_id ], unique: true
    add_index :voting_votes, :user_id
    add_check_constraint :voting_votes, "value IS NULL OR value IN ('up', 'down')", name: "voting_votes_value_valid"
  end
end
