#!/bin/sh
# First-time Mastodon initialization: creates the schema, seeds, and
# creates an owner account named `tester` so the interop test script
# has someone to act as.
#
# Run AFTER `docker compose up -d` has the db + redis healthy. Safe
# to re-run — Rails db:setup is idempotent (skips if schema already
# exists). Account creation will say "already exists" if you've run
# this before.

set -e

cd "$(dirname "$0")/.."

COMPOSE="docker compose -f docker-compose.federation-test.yml"

echo "[mastodon-setup] Setting up the database..."
$COMPOSE run --rm mastodon_web bundle exec rails db:setup

echo "[mastodon-setup] Generating proper VAPID keypair..."
$COMPOSE run --rm mastodon_web bin/tootctl webpush:generate_vapid_key \
  || echo "(VAPID generation skipped — already set or web push not needed for federation test)"

echo "[mastodon-setup] Creating admin account 'tester'..."
$COMPOSE run --rm mastodon_web \
  bin/tootctl accounts create tester \
    --email tester@mastodon.arab.place \
    --confirmed \
    --role Owner \
  || echo "(tester account creation skipped — may already exist)"

echo
echo "[mastodon-setup] Done. Admin login at https://mastodon.arab.place/auth/sign_in"
echo "  Email:    tester@mastodon.arab.place"
echo "  Password: shown above by tootctl (only printed once — copy it!)"
