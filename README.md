# Billetto Events

A Rails 8 application that ingests public events from the **Billetto API**, lists them, and lets
users authenticated with **Clerk** like or dislike them. Votes are recorded as facts in
**Rails Event Store** and projected into read models.

The focus is on backend architecture: event-driven design, clear module boundaries, side effects,
resilience and scalability. The UI is deliberately plain.

> **Note on the Billetto API.** Billetto doesn't operate in India: organiser accounts, and with them
> API key pairs, are only available in the UK and the EU countries Billetto serves. I was therefore
> not able to set up an API key and use the live Billetto API from India.
>
> The Billetto integration is still fully implemented and tested against the API contract: the HTTP
> client with retries, timeouts and pagination, the payload translation and validation, and the
> idempotent sync job. Without a key, the app imports deterministic sample events through exactly
> the same pipeline, and a banner on the page says "Running with fake Billetto integration".
> Adding `BILLETTO_API_KEYPAIR=<key id>:<secret>` to `.env` and running `bin/rails billetto:sync`
> switches it to live Billetto data, with no code changes. See [Assumptions](#assumptions).

---

## Contents

1. [Quick start](#quick-start)
2. [Configuration](#configuration)
3. [Running the tests](#running-the-tests)
4. [Architecture](#architecture)
5. [Design choices](#design-choices)
6. [Scalability & performance](#scalability--performance)
7. [Assumptions](#assumptions)
8. [What I would do next](#what-i-would-do-next)

---

## Quick start

Requirements: Ruby 3.2+ (tested on 3.2.2), PostgreSQL 14+ (tested on 14.17), Chrome (for the browser tests). Redis is optional
(only needed with Sidekiq).

```bash
bundle install
cp .env.example .env            # optional: add Billetto / Clerk keys
bin/rails db:prepare            # creates DB, runs migrations (incl. Rails Event Store tables)
bin/rails db:seed               # imports events through the real ingestion pipeline
bin/dev                         # http://localhost:3000
```

**No credentials?** The app still runs end to end. Without `BILLETTO_API_KEYPAIR`,
development uses `Billetto::FakeAdapter`, which returns deterministic sample events. Without
`CLERK_PUBLISHABLE_KEY`, it uses a local fake of clerk-js, with sign-up, sign-in and sign-out
that behave like Clerk. A banner shows which integrations are fake. Each integration is
switched independently.

Useful URLs in development:

| URL | What |
| --- | --- |
| `/` | Upcoming events with like/dislike counts |
| `/sign_up`, `/sign_in` | Clerk `<SignUp/>` / `<SignIn/>` components |
| `/res` | Rails Event Store browser: streams, facts, correlation/causation chains |
| `/up` | Health check |

Postgres and Redis via Docker (optional): `docker compose up -d`, then set
`DATABASE_USERNAME=postgres DATABASE_PASSWORD=postgres`.

One command checks everything (install, databases, autoloading, RSpec incl. browser tests, RuboCop,
Playwright) and writes `log/verify.log`:

```bash
bin/verify
```

**Verified on:** macOS (Apple Silicon), Ruby 3.2.2, Rails 8.1.4.1, Rails Event Store 2.19.3,
PostgreSQL 14.17, Node 23. Result: **123 RSpec examples, 0 failures, 97.5 % line coverage**,
RuboCop 0 offenses, Playwright end-to-end passing. Sign-up, sign-in, voting and sign-out were also
checked manually against a real Clerk development instance.

## Configuration

All configuration is read from environment variables. `.env` is loaded in development and test.

| Variable | Purpose |
| --- | --- |
| `BILLETTO_API_KEYPAIR` | `key_id:secret` from Billetto → Organiser → Integrate → Developers → API keys |
| `BILLETTO_API_BASE_URL` | Defaults to `https://billetto.dk/api/v3`. Change it for other regions |
| `CLERK_PUBLISHABLE_KEY` | Clerk publishable key. The Frontend API host and the clerk-js / Clerk UI script URLs are derived from it |
| `CLERK_JS_VERSION`, `CLERK_UI_VERSION` | Major versions of clerk-js (default `6`) and `@clerk/ui` (default `1`) loaded from your Frontend API |
| `CLERK_SECRET_KEY` | Optional. When set, the JWKS is fetched from the Backend API |
| `CLERK_JWT_KEY` | Optional PEM public key for fully networkless JWT verification |
| `CLERK_AUTHORIZED_PARTIES` | Comma-separated origins accepted in the token's `azp` claim, e.g. `http://localhost:3000` |
| `CLERK_WEBHOOK_SIGNING_SECRET` | Svix signing secret of the Clerk webhook endpoint (`POST /webhooks/clerk`) |
| `FAKE_BILLETTO`, `FAKE_CLERK`, `FAKE_INTEGRATIONS` | Force fake/real adapters. Fakes are refused in production |
| `ACTIVE_JOB_ADAPTER` | Development defaults to `async` (in-process). Use `sidekiq` with Redis |

### Importing events

```bash
bin/rails billetto:sync                       # all pages, inline
MAX_PAGES=5 PAGE_SIZE=100 bin/rails billetto:sync
ASYNC=1 bin/rails billetto:sync               # enqueue Billetto::SyncPublicEventsJob
```

In production, schedule `Billetto::SyncPublicEventsJob` with cron, sidekiq-cron or Solid Queue
recurring tasks. Re-running is idempotent and cheap.

### Clerk setup

1. Create a Clerk application and enable email + password. For testing, any address containing
   `+clerk_test` (e.g. `you+clerk_test@example.com`) accepts the verification code `424242`.
2. Put the publishable key and secret key in `.env`.
3. Optionally, add a webhook endpoint `https://<host>/webhooks/clerk` for `user.created`,
   `user.updated` and `user.deleted`, and set `CLERK_WEBHOOK_SIGNING_SECRET`. Use ngrok or
   similar for local testing.

## Running the tests

```bash
RAILS_ENV=test bin/rails db:prepare
bin/rspec                         # whole suite (unit, integration, request, browser)
COVERAGE=1 bin/rspec              # with SimpleCov report in coverage/
HEADLESS=false bin/rspec spec/system   # watch the browser tests
```

| Required by the assignment | Spec |
| --- | --- |
| Model tests (title presence, date validation, ...) | `spec/domain/catalog/event_spec.rb` |
| Authentication tests (voting restricted to signed-in users) | `spec/requests/votes_spec.rb` |
| Event Store tests (vote facts created and counted correctly) | `spec/domain/voting/voting_spec.rb`, `spec/domain/read_models/event_vote_tally_spec.rb` |
| Browser test (sign-up, login, logout, voting) | `spec/system/authentication_and_voting_spec.rb` (Capybara + Cuprite/headless Chrome) |

Also covered:

- Billetto adapter: auth header, pagination, retries, timeouts, host pinning.
- Payload translation and the idempotent sync job.
- Clerk JWT verification: expiry, nbf, wrong key, algorithm confusion, `azp`, key rotation, networkless mode.
- Svix webhook signatures and the webhook pipeline.
- Command bus: validation, transactions, instrumentation, correlation/causation.
- `Handler.async` after-commit semantics.
- Keyset pagination.
- Cross-module integrator.

The suite never touches the network. Business-level tests use the fake adapters, as the
Developer's Guide recommends. HTTP is stubbed with WebMock only in the adapter specs.

### Playwright end-to-end tests (live server)

```bash
cd e2e && npm install && npx playwright install chromium
npx playwright test                              # against the fake Clerk (no keys needed)
E2E_REAL_CLERK=1 npx playwright test             # against your real Clerk *development* instance
```

The real-Clerk run uses `@clerk/testing` Testing Tokens. It also uses Clerk's test email
addresses (`+clerk_test`, verification code `424242`), so no real email is sent.

## Architecture

```
app/
  domain/                 bounded contexts (Developer's Guide layout)
    catalog.rb            Catalog facts: EventImported, EventDetailsChanged
    catalog/              Event model, ImportEvents command, Service (command handler)
    voting.rb             Voting facts: EventUpvoted, EventDownvoted, VoteWithdrawn
    voting/               Vote (write model), CastVote / WithdrawVote / WithdrawAllVotes
    identity.rb           Identity facts: UserRegistered, UserProfileUpdated, UserDeleted
    identity/             User projection of Clerk users, SyncUser / DeleteUser, Service
    read_models/          EventVoteTally (+ async Projector), ProcessedFact idempotency ledger
  integrations/           anti-corruption layers for 3rd parties
    billetto/             Adapter (HTTP), FakeAdapter, EventRecord translator, SyncPublicEventsJob
    clerk_auth/           Adapter (JWT/JWKS), FakeAdapter, WebhookVerifier (Svix), WebhookJob
  integrators/            cross-module process: IdentityIntegrators::WithdrawVotesWhenUserDeleted
  queries/                EventListing (read side of the events page)
  controllers/            thin: parse params -> command -> command bus
lib/
  fact.rb                 base domain event with SCHEMA + stream_names
  command.rb, command/    Command::Executable / Command::Handler + bus chain
  handler.rb              Handler.sync / Handler.async(queue:) + after-commit AsyncJob
  application_subscriptions.rb, application_command_bus.rb, application_event_store.rb
  object_repository.rb, has_typeid.rb, type_id.rb
```

### Request flow: casting a vote

```
POST /events/:tid/vote ──► Events::VotesController (auth: Clerk JWT from __session cookie)
   │ command_bus.call(Voting::CastVote)
   ▼
InstrumentedBus ► ValidatingBus ► CorrelationBus ► TransactionalBus ► Bus
                                                     │ BEGIN
   Vote.ballot_for!(event, user)   (row lock, unique index)
   vote.cast!("up") ─► UPDATE voting_votes
                   └─► publish EventUpvoted ─► stream "Voting::Event$<tid>"
                                              └ link  "Voting::User$<user>"
                                                     │ COMMIT
   after commit ─► Handler::AsyncJob(read_models queue)
                     └─► EventVoteTally::Projector (idempotent, atomic upsert of +1/-1 deltas)
```

### Ingestion flow

```
SyncPublicEventsJob ─► Billetto::Adapter#each_page (cursor pagination, retries)
   │   page ─► Billetto::EventRecord (ACL translation, structural validation)
   ▼
command_bus.call(Catalog::ImportEvents)   one short transaction per page
   advisory lock per source ─► 1 SELECT digests ─► 1 upsert (new+changed) ─► 1 UPDATE (unchanged)
   ─► EventImported / EventDetailsChanged facts only for real changes
   ─► Billetto::PublicEventsSynced summary fact at the end
```

## Design choices

**Developer's Guide conventions.**

- Modules in `app/domain` with `Module.subscriptions`, registered in `ApplicationSubscriptions`.
- Facts with a `SCHEMA` validated by `.strict`, and `stream_names`. The first stream is the main
  stream and the rest are linked.
- Self-executing commands (`Command::Executable`) and command handler services (`Command::Handler`).
  Both run only through the command bus.
- Thin controllers.
- `Handler.async(queue:)` for process managers, integrators and read models.
- `ObjectRepository` with `has_typeid`.
- ACL integrations in `app/integrations` with fake adapters for tests.
- Integrators in `app/integrators`.
- Webhooks are stored first, then processed asynchronously.

**Command bus as a chain of responsibility.**

- Instrumentation, validation, correlation and causation ids, and transactions are separate
  links (`lib/command/*`).
- The state change, the facts and the sync handlers commit or roll back together. The write
  model and the event log never diverge.
- A command sent while handling a fact automatically gets `correlation_id` / `causation_id`.
  The RES browser can then show, for example, *UserDeleted → VoteWithdrawn*.

**Voting: state + facts, not pure event sourcing.**

- `Voting::Vote` holds a user's current ballot. Its row lock and unique index give simple,
  race-free invariants (one vote per user per event, idempotent re-votes, switches, withdrawals).
- Every change publishes a fact that carries the user id. The fact goes into the event's stream
  and is linked into the user's stream, for traceability.
- This is the Guide's style: a domain object that publishes facts. It avoids rebuilding an
  aggregate from its stream on every click.
- `AggregateRoot` would be a drop-in alternative if the voting rules grew more complex.

**Counts are a read model.**

- `EventVoteTally` is projected **asynchronously** from the facts. A slow or failing projection
  never blocks or fails a vote.
- It is **idempotent**: a `processed_facts` ledger is written in the same transaction, because
  delivery is at-least-once.
- It is **order-independent**, because it applies commutative ±1 deltas, using
  `previous_vote` carried in the fact.
- It is **lock-free**: one `INSERT … ON CONFLICT DO UPDATE SET upvotes = upvotes + EXCLUDED.upvotes`
  statement per fact, so hot events don't create read-modify-write races.
- It can be rebuilt from the event store: `bin/rails read_models:rebuild_vote_tallies`.
- The user's own vote is read from the write model, so it is visible immediately
  (read-your-writes). Counts are eventually consistent, on the order of milliseconds.

**Async handlers after commit.**

- `Handler.async` enqueues only after the publishing transaction commits
  (`ActiveRecord.after_all_transactions_commit`). Jobs therefore never run before their data
  is visible.
- Jobs are never enqueued for rolled-back work.
- The job carries only the fact id and re-reads the fact from the event store. Payloads stay
  tiny and there is a single source of truth.

**Billetto ACL.**

- No Billetto payload or Faraday exception leaves `app/integrations/billetto`.
- Validation has two layers:
  1. The ACL rejects structurally broken records, with a reason.
  2. The `Catalog::Event` model and DB constraints enforce business rules: dates, URLs, price
     and currency, uniqueness.
- Invalid records are reported and skipped. They never fail the whole batch.
- Resilience:
  - Timeouts, plus retries with exponential backoff and jitter for timeouts, 429 and 5xx.
  - `Retry-After` is honoured.
  - Errors are typed, and the job maps them to retry or discard (a wrong keypair is never retried).
  - `next_url` is only followed on the configured host, so the keypair can't leak.

**Clerk.**

- Clerk's **JS SDK** handles sign-up, sign-in and sign-out via its prebuilt components. The app
  follows Clerk Core 3: clerk-js v6 plus the separate `@clerk/ui` bundle, passed to
  `Clerk.load({ ui: { ClerkUI } })`. New Clerk instances reject the older clerk-js v5.
- The server verifies the short-lived session JWT from the `__session` cookie (or a `Bearer`
  header): RS256 against the JWKS, `exp`/`nbf`, `azp`.
- This is Clerk's documented *manual JWT verification*. I chose it over the `clerk-sdk-ruby`
  Rack middleware for three reasons:
  - It is networkless after the JWKS is cached (or fully networkless with `CLERK_JWT_KEY`).
  - Public pages have no per-request middleware cost.
  - The vendor stays behind an ACL with a fake for tests.
- JWKS key rotation is handled. Unknown `kid`s force a refetch, throttled so garbage tokens
  can't hammer Clerk.
- Clerk webhooks keep a local `Identity::User` projection in sync:
  - Signatures are verified Svix-style, with replay protection.
  - Deliveries are deduplicated on `svix-id`.
  - `user.deleted` scrubs personal data and withdraws the user's votes through an integrator.

**TypeIDs.**

- Public identifiers look like `event_01j…`: UUIDv7-based and time-ordered, so they are
  index-friendly.
- They are not enumerable, unlike integer ids, and they tell you their type at a glance.
- `ObjectRepository.find(tid)` resolves any object without knowing its table.

## Scalability & performance

- **Ingestion is set-based**: three statements per page, whatever the page size. Each page runs
  in its own short transaction, memory use is flat, and a transaction-scoped advisory lock
  serializes concurrent syncs of the same source.
- **Facts only for real changes**: content digests detect changes, so a sync with no changes
  writes no facts.
- **Listing uses two queries per page**: events joined with tallies, plus the viewer's votes.
  Keyset pagination on an `(starts_at, id)` index keeps every page O(log n), with no `OFFSET`
  scans.
- **The voting path is short**: one row lock, one update, one fact insert plus a link.
  Counters are moved off the write path.
- **Queues are separated** (`critical` webhooks > `default` / `read_models` > `low`
  ingestion), so a big import never delays webhook processing or projections.
- **Votes are rate limited** per user (Rails 8 `rate_limit`, 30/min).
- **Facts use jsonb storage** (`RailsEventStore::JSONClient`), so facts can be queried and
  indexed.

## Assumptions

- **Billetto API access.** Billetto organiser accounts (and therefore API keypairs) are only
  available in the UK and EU countries Billetto operates in, so I could not create a keypair from
  India. The integration is fully built and tested against the documented contract (adapter specs
  with WebMock, translator, idempotent sync job); without `BILLETTO_API_KEYPAIR` the app imports
  deterministic sample events through the very same pipeline (banner: "Running with fake Billetto
  integration"). Adding a keypair to `.env` and running `bin/rails billetto:sync` switches to live data.
- The Billetto endpoint is `GET {base}/public/events` with the `Api-Keypair: key:secret` header.
  It returns an `object: "list"` envelope with `data[]`, `has_more` and `next_url`. I couldn't
  call the API from my build environment, so the translator is deliberately tolerant
  (`startdate`/`start_date`, `image_link`/`image_url`, ...). It also keeps the raw payload in
  `raw_payload` for re-processing.
- Events without a start date are skipped and reported. One example is recurring `kind: "regular"`
  events.
- "Upcoming" means starting today or later, in UTC. Ongoing multi-day events that started
  earlier are not listed.
- Event pages and counts are public. Only voting requires authentication.
- One vote per user per event. Clicking your current vote withdraws it. Switching between like
  and dislike is allowed.
- Votes reference events by TypeID across module boundaries, with no cross-module foreign key.
  Existence is checked in the command.
- Development defaults to in-process async jobs, so Redis isn't required to try the app.
  Production uses Sidekiq.
