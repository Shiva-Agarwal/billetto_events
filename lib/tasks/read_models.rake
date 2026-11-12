namespace :read_models do
  desc "Rebuild event vote tallies from the facts stored in Rails Event Store"
  task rebuild_vote_tallies: :environment do
    count = ReadModels::EventVoteTally.rebuild!
    puts "Rebuilt vote tallies for #{count} events"
  end

  desc "Delete idempotency ledger entries older than DAYS (default 30)"
  task prune_processed_facts: :environment do
    days = ENV.fetch("DAYS", 30).to_i
    deleted = ReadModels::ProcessedFact.where(created_at: ...days.days.ago).delete_all
    puts "Deleted #{deleted} processed fact entries older than #{days} days"
  end
end
