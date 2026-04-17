# Federation interop testbed

Runs HybridSocial on `arab.place` + a fresh Mastodon instance on
`mastodon.arab.place`, both fronted by Caddy with auto Let's Encrypt.
Used to verify our ActivityPub implementation actually federates with
real Mastodon — not just spec-reading guesses.

## Prerequisites on the host

* Docker (with compose v2)
* `arab.place` and `mastodon.arab.place` DNS A/AAAA records pointing
  at this server
* Ports 80, 443 open inbound

## Deploy

```sh
cd /opt/hybridsocial-federation-test    # or wherever you cloned to

# 1. Outer env (HybridSocial side)
cp .env.federation-test.example .env
$EDITOR .env       # set ACME_EMAIL, HS_DB_PASSWORD, MASTODON_DB_PASSWORD

sh ../docker/generate-secrets.sh .env   # auto-fills HS_SECRET_KEY_BASE + RSA keys

# 2. Mastodon env
sh scripts/generate-mastodon-secrets.sh .env

# 3. Boot. First build will take ~10 min (HybridSocial backend release + frontend build).
docker compose -f docker-compose.federation-test.yml up -d

# 4. One-time Mastodon DB setup + admin account
sh scripts/mastodon-first-time-setup.sh

# 5. Create a HybridSocial admin via Phoenix release
docker compose -f docker-compose.federation-test.yml exec hs_backend \
  bin/hybridsocial eval "Hybridsocial.Release.setup()"

# Then register the `tester` account through the UI at https://arab.place
# (or via the API /api/v1/auth/register).

# 6. Run the protocol-level smoke tests
sh scripts/federation-interop-test.sh
```

## What the test script checks

* WebFinger discovery (both directions)
* Actor JSON shape + `@context` array (the spec compliance fix)
* Content-Type negotiation (`application/activity+json` AND `application/ld+json`)
* NodeInfo discovery
* Outbox returns `OrderedCollection`

What it CAN'T script (do manually via the UIs):

* Follow handshake (requires user auth + UI action)
* Post creation + delivery
* Likes / reactions / replies round-trip

## Tear down

```sh
docker compose -f docker-compose.federation-test.yml down -v
```

## Notes

* The testbed deliberately omits CrowdSec + Coraza (those live in
  `../docker-compose-production.yml`). Their absence makes interop
  failures easier to diagnose — when this passes we know the
  federation layer itself is correct, separate from the WAF.
* HybridSocial backend image is built from `../backend/Dockerfile`,
  frontend from `../frontend/Dockerfile`. Re-deploying after code
  changes: `docker compose -f docker-compose.federation-test.yml up
  -d --build hs_backend hs_frontend`.
* Mastodon storage is bind-volume-only (no S3) — fine for testing,
  not for any real workload.
