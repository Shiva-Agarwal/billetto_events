# Seeds the catalog through the same ingestion path as production (adapter -> ACL -> command).
# Without BILLETTO_API_KEYPAIR the fake adapter provides deterministic sample events.
if Catalog::Event.none?
  totals = Billetto::SyncPublicEventsJob.perform_now(max_pages: ENV.fetch("MAX_PAGES", 2).to_i)
  puts "Imported events: #{totals.inspect}"
else
  puts "Catalog already has #{Catalog::Event.count} events - skipping (run bin/rails billetto:sync to refresh)"
end
