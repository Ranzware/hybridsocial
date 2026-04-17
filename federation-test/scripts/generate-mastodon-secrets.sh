#!/bin/sh
# Generate Mastodon required secrets and write them into
# federation-test/mastodon/.env.production. Idempotent — already-set
# values are preserved.

set -e

cd "$(dirname "$0")/.."

ENV_FILE="mastodon/.env.production"
EXAMPLE_FILE="mastodon/.env.production.example"

if [ ! -f "$ENV_FILE" ]; then
  echo "[mastodon-secrets] Bootstrapping $ENV_FILE from example."
  cp "$EXAMPLE_FILE" "$ENV_FILE"
fi

# Reads the outer .env to get the DB password and writes it into
# the Mastodon env so DB_PASS matches what the postgres container
# was started with.
if [ -f .env ]; then
  outer_db_pass=$(grep '^MASTODON_DB_PASSWORD=' .env | cut -d= -f2-)
  if [ -n "$outer_db_pass" ]; then
    sed -i "s|^DB_PASS=.*|DB_PASS=$outer_db_pass|" "$ENV_FILE"
  fi
fi

set_secret() {
  key="$1"
  generator="$2"

  current=$(grep "^${key}=" "$ENV_FILE" | cut -d= -f2-)

  if [ -n "$current" ] && [ "$current" != "" ]; then
    echo "[mastodon-secrets] $key already set, skipping."
    return
  fi

  value=$(eval "$generator")
  sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  echo "[mastodon-secrets] $key generated."
}

# `tootctl secret` and `bundle exec rails secret` aren't available
# without booting the rails app, so we generate compatible values
# directly with openssl. Each is 128 hex chars (64 bytes) which is
# what Mastodon's own generators emit.

set_secret SECRET_KEY_BASE "openssl rand -hex 64"
set_secret OTP_SECRET "openssl rand -hex 64"

# VAPID for web push — RFC 8292 P-256 keypair, base64url-encoded.
if ! grep -q "^VAPID_PRIVATE_KEY=." "$ENV_FILE"; then
  echo "[mastodon-secrets] Generating VAPID keypair..."

  # Generate the private key as a P-256 EC key, then derive the public.
  vapid_private=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null \
    | openssl ec -outform DER 2>/dev/null \
    | tail -c +8 | head -c 32 \
    | base64 -w 0 | tr '+/' '-_' | tr -d '=')

  # Mastodon expects the public key in base64url too. Easiest: generate
  # via tootctl after first boot. For now, set placeholder so the env
  # parses; container will fail-fast if push notifications attempted.
  vapid_public="BPlaceholderRunTootctlVapidGenerateAfterFirstBoot"

  sed -i "s|^VAPID_PRIVATE_KEY=.*|VAPID_PRIVATE_KEY=${vapid_private}|" "$ENV_FILE"
  sed -i "s|^VAPID_PUBLIC_KEY=.*|VAPID_PUBLIC_KEY=${vapid_public}|" "$ENV_FILE"
  echo "[mastodon-secrets] VAPID keys set (regenerate with: docker compose run --rm mastodon_web bin/tootctl webpush:generate_vapid_key)."
fi

# ActiveRecord encryption (Mastodon 4.3+). Three independent random
# strings; rails has its own generator but openssl works fine.
set_secret ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY "openssl rand -hex 32"
set_secret ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY "openssl rand -hex 32"
set_secret ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT "openssl rand -hex 32"

echo
echo "[mastodon-secrets] Done. $ENV_FILE is ready."
