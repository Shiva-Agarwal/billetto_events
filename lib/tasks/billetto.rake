namespace :billetto do
  desc "Import public events from Billetto. Options: MAX_PAGES=10 PAGE_SIZE=100 ASYNC=1"
  task sync: :environment do
    options = {
      max_pages: ENV["MAX_PAGES"]&.to_i,
      page_size: ENV.fetch("PAGE_SIZE", 50).to_i
    }
    if ENV["ASYNC"].present?
      Billetto::SyncPublicEventsJob.perform_later(**options)
      puts "Enqueued Billetto::SyncPublicEventsJob #{options.inspect}"
    else
      totals = Billetto::SyncPublicEventsJob.perform_now(**options)
      puts "Billetto sync finished: #{totals.inspect}"
    end
  end
end
