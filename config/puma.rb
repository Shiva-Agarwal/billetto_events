threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count
port ENV.fetch("PORT", 3000)
workers ENV.fetch("WEB_CONCURRENCY", 0)
preload_app! if ENV.fetch("WEB_CONCURRENCY", 0).to_i > 1
plugin :tmp_restart
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
