# Command log

This file has three parts:

1. **Build from scratch.** The generator-based commands that produce this codebase. In my build
   environment, rubygems.org was blocked, so I wrote every file by hand to match what these
   commands would generate.
2. **Setup, run and test.** What you run on your machine.
3. **Commands executed in this build session**, in order.

---

## 1. Build from scratch (generator equivalents)

```bash
# Toolchain
rbenv install 3.3.6 && rbenv local 3.3.6        # or: rvm install 3.3.6 && rvm use 3.3.6
gem install rails -v "~> 8.0"
brew install postgresql@16 && brew services start postgresql@16   # macOS (or: docker compose up -d)

# App skeleton: API-light Rails app on PostgreSQL, RSpec instead of Minitest, no unused frameworks
rails new billetto_events --database=postgresql --skip-test --skip-javascript --skip-hotwire \
  --skip-jbuilder --skip-action-mailer --skip-action-mailbox --skip-action-text \
  --skip-active-storage --skip-action-cable --skip-solid --skip-kamal --skip-thruster --skip-docker
cd billetto_events

# Runtime gems
bundle add rails_event_store --version "~> 2.15"
bundle add sidekiq --version "~> 7.3"
bundle add faraday --version "~> 2.12"
bundle add faraday-retry --version "~> 2.2"
bundle add jwt --version "~> 2.9"

# Dev/test gems
bundle add rspec-rails factory_bot_rails dotenv-rails --group "development, test"
bundle add ruby_event_store-rspec webmock capybara cuprite --group test
bundle add simplecov --group test --require false

# RSpec
bin/rails generate rspec:install

# Rails Event Store tables (PostgreSQL jsonb variant)
bin/rails generate rails_event_store_active_record:migration --data-type=jsonb

# Domain tables
bin/rails generate migration CreateCatalogEvents
bin/rails generate migration CreateVotingVotes
bin/rails generate migration CreateReadModelTables
bin/rails generate migration CreateIdentityUsersAndIncomingWebhooks

# Database
bin/rails db:create
bin/rails db:migrate          # also writes db/schema.rb

# Playwright E2E project
mkdir e2e && cd e2e
npm init -y
npm install -D @playwright/test @clerk/testing dotenv
npx playwright install chromium
cd ..
```

## 2. Setup, run and test

```bash
# One-time setup
bundle install
cp .env.example .env                      # add BILLETTO_API_KEYPAIR / CLERK_* keys (optional)
bin/rails db:prepare                      # create + migrate development DB (writes db/schema.rb)
RAILS_ENV=test bin/rails db:prepare       # create + load test DB

# Data
bin/rails db:seed                         # first import through the real ingestion pipeline
bin/rails billetto:sync                   # (re)import from Billetto
MAX_PAGES=5 PAGE_SIZE=100 bin/rails billetto:sync
ASYNC=1 bin/rails billetto:sync           # enqueue as a background job

# Run
bin/dev                                   # web on :3000 (in-process async jobs)
ACTIVE_JOB_ADAPTER=sidekiq bin/rails s    # with Sidekiq...
bundle exec sidekiq -C config/sidekiq.yml # ...and a worker (needs Redis)

# Tests
bin/rspec                                 # full suite
bin/rspec spec/domain/catalog/event_spec.rb               # model tests
bin/rspec spec/requests/votes_spec.rb                     # authentication tests
bin/rspec spec/domain/voting spec/domain/read_models      # event store tests
bin/rspec spec/system                                     # browser test (headless Chrome)
HEADLESS=false bin/rspec spec/system                      # watch it
COVERAGE=1 bin/rspec                                      # coverage report -> coverage/index.html
bundle exec rubocop                                       # lint

# Playwright end-to-end (boots its own server on :3100)
cd e2e && npm install && npx playwright install chromium
npx playwright test                       # fake Clerk
E2E_REAL_CLERK=1 npx playwright test      # real Clerk dev instance (keys in ../.env)
npx playwright show-report

# Read models / maintenance
bin/rails read_models:rebuild_vote_tallies
DAYS=30 bin/rails read_models:prune_processed_facts

# Event store browser
open http://localhost:3000/res
```

## 3. Commands executed in this build session

Environment checks (rubygems.org, npm and api.billetto.com were blocked with HTTP 403 in both
available sandboxes, so no gems could be installed):

```bash
pdftotext -layout <each attached PDF> -        # read the assignment, test spec and Developer's Guide
which ruby gem bundle rails psql pg_ctl mysql redis-server node npm yarn chromium google-chrome sqlite3
ruby -v; gem list
gem search -r '^rails$'                                          # -> blocked
curl -sS -o /dev/null -w "%{http_code}" https://rubygems.org/api/v1/gems/rails.json   # -> 403
curl -sS -o /dev/null -w "%{http_code}" https://api.billetto.com/api/v3/public/events # -> 403
curl -sS -o /dev/null -w "%{http_code}" https://registry.npmjs.org/                   # -> blocked
pg_lsclusters
curl -sS "$HTTPS_PROXY/__agentproxy/status"
# same reachability checks repeated in the Linux sandbox on the Mac -> 403
```

Project creation (files were written with the editor; shell commands used):

```bash
mkdir -p billetto_events && cd billetto_events
mkdir -p app/{controllers/{events,webhooks,concerns},domain/{catalog,voting,identity,read_models/event_vote_tally},\
integrations/{billetto,clerk_auth},integrators,models,jobs,helpers,queries,views/{layouts,events,auth}} \
  app/assets/stylesheets bin config/{environments,initializers,locales} db/migrate lib/{command,handler,tasks} \
  log tmp public vendor/fake_clerk spec/{support,factories,fixtures/billetto,lib,system,integrators} \
  spec/domain/{catalog,voting,read_models,identity} spec/integrations/{billetto,clerk_auth} spec/requests/webhooks \
  e2e/tests .github/workflows
echo "3.3.6" > .ruby-version
chmod +x bin/*
touch log/.keep tmp/.keep
```

Verification:

```bash
for f in $(find . -name "*.rb"); do ruby -c "$f" > /dev/null || echo "FAIL $f"; done   # all Ruby files: Syntax OK
node --check vendor/fake_clerk/clerk.js                                                # fake clerk-js: OK
```

Packaging and delivery:

```bash
cd .. && tar --exclude='./billetto_events/log/*' --exclude='./billetto_events/tmp/*' \
  -czf billetto_events.tar.gz billetto_events
# extracted into ~/projects/billetto_events on your Mac
```

### Verification runs on the Mac (Ruby 3.2.2, PostgreSQL 14.17, Node 23, Rails 8.1.4.1, RES 2.19.3)

```bash
cd ~/projects/billetto_events && bin/verify      # run 1: 114/123 green, RSpec 9 failures, Playwright failed
cd ~/projects/billetto_events && bin/verify      # run 2: 122/123 green, 1 browser failure, RuboCop parser config
cd ~/projects/billetto_events && bin/verify      # run 3: ALL GREEN
# (Clerk Core 3 switch: clerk-js v6 + @clerk/ui; manual sign-up/vote checked against real Clerk)
cd ~/projects/billetto_events && bin/verify      # run 4: ALL GREEN (123/0, 97.5 % coverage) - final
```

`bin/verify` executes, in order:

```bash
bundle install --jobs 4
bin/rails db:prepare
RAILS_ENV=test bin/rails db:prepare
bin/rails zeitwerk:check
bin/rails db:seed
COVERAGE=1 bin/rspec
bundle exec rubocop
cd e2e && npm install && npx playwright install chromium && npx playwright test
```

Final result: **123 examples, 0 failures**, line coverage **97.5%**, RuboCop **0 offenses**,
Playwright **1 passed** (fake Clerk), 1 skipped (real Clerk, needs `E2E_REAL_CLERK=1` + secret key).

Fixes made between runs:

| Run | Problem | Fix |
| --- | --- | --- |
| 1 | Fake clerk-js served as JS was blocked by Rails cross-origin JS protection (422) | `skip_forgery_protection` on `FakeClerkController` |
| 1 | RES 2.19 batch API | `read.of_type(...).in_batches(n).each_batch` |
| 1 | `RubyEventStore::Metadata` is not a Hash | assert on `metadata.to_h` |
| 1 | HTML5 sanitizer kept `<script>` text | strip script/style blocks before sanitizing |
| 1 | Digest missing on `save(validate: false)` | also compute digest `before_save` |
| 1 | JWT spec helper swallowed claims as keywords | `def token(key:, kid:, algorithm:, **claims)` |
| 1 | RVM warning on `ruby ">= 3.2.0"` in Gemfile | removed the directive |
| 2 | Submit interceptor in the Clerk bridge never re-submitted vote forms | removed it; refresh session cookie on focus/visibility instead |
| 2 | RuboCop fell back to the Ruby 2.7 parser | `TargetRubyVersion: 3.2` in `.rubocop.yml` |

Clerk setup (built-in browser, Clerk Dashboard): verified the development instance
`logical-chicken-519.clerk.accounts.dev` (email + password enabled, RS256 JWKS, clerk-js v5/v6 reachable)
and wrote `CLERK_PUBLISHABLE_KEY` + `CLERK_AUTHORIZED_PARTIES` into `.env`.
