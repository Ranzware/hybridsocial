# HybridSocial on Coolify — Deployment Guide

This guide walks through deploying HybridSocial on a Coolify-managed
server using the project's production Docker Compose stack.

## Prerequisites

- A **Coolify** instance (v4.x) running on a VPS
- A domain name with DNS access (e.g. `social.example.com`)
- A **Cloudflare** account (recommended — the Caddyfile is pre-configured
  for Cloudflare proxy mode with `tls internal`)
- At least **4 GB RAM** on the target server (OpenSearch + ClamAV are the
  heaviest services; 2 GB minimum if you disable ClamAV)
- Ports **80** and **443** available on the target server

## Architecture Overview

```
Internet → Cloudflare (TLS) → Caddy (WAF + CrowdSec) → Backend / Frontend
                                        ↓
                                  Postgres, Valkey, NATS, OpenSearch, ClamAV
```

The production compose (`docker-compose-production.yml`) runs **10 services**:

| Service        | Purpose                          | Port |
|----------------|----------------------------------|------|
| `caddy`        | Reverse proxy + WAF + CrowdSec   | 80, 443 |
| `backend`      | Phoenix API + federation         | 4000 (internal) |
| `frontend`     | SvelteKit SSR                    | 3000 (internal) |
| `postgresql`   | Database                         | 5432 (internal) |
| `valkey`       | Cache / rate limiting            | 6379 (internal) |
| `nats`         | Message broker (JetStream)       | 4222 (internal) |
| `opensearch`   | Full-text search                 | 9200 (internal) |
| `clamav`       | Antivirus scanner                | 3310 (internal) |
| `crowdsec`     | Behavioral IP blocking           | 8080 (internal) |
| `backend-migrate` | One-shot DB migration         | — |

Only Caddy exposes ports to the host (80/443). Everything else is on an
internal Docker bridge network.

---

## Step 1 — Prepare Your Domain

Point DNS records at your Coolify server's public IP:

```
A     social.example.com     → <server IP>
A     media.social.example.com → <server IP>     (optional, recommended)
```

If using Cloudflare (recommended):
- Set both records to **Proxied** (orange cloud)
- SSL/TLS mode: **Full** (not Full Strict — Caddy uses `tls internal`)
- This means Cloudflare terminates public TLS; Caddy uses a self-signed
  cert internally, which Cloudflare accepts under "Full" mode

The `media.social.example.com` subdomain serves user uploads from a
separate origin (no cookies, `Content-Security-Policy: default-src 'none'`,
`X-Content-Type-Options: nosniff`). Configure it in the `MEDIA_HOST` and
`MEDIA_DOMAIN` env vars.

---

## Step 2 — Create the Coolify Resource

1. Open your Coolify dashboard
2. Click **+ New Resource** → **Docker Compose Empty** (or "Choose a
   GitHub repository" if your fork is on GitHub)
3. If using GitHub: connect your repo, set **Base path** to `/` and the
   **Compose file** to `docker-compose-production.yml`
4. If creating empty: paste the contents of `docker-compose-production.yml`
   into the compose editor, or set the file path

### Critical: Disable Coolify's Proxy

The project ships its own Caddy reverse proxy with WAF, CrowdSec, and
Cloudflare integration. You must **disable Coolify's built-in proxy**
for this resource to avoid a port conflict on 80/443:

1. In the resource settings, find the **Proxy** section
2. Set it to **None** (or "No Proxy")
3. This lets the project's Caddy bind 80/443 directly on the host

If you can't disable Coolify's proxy (e.g. other apps need it on 80/443),
see [Alternative: Behind Coolify's Proxy](#alternative-behind-coolifys-proxy)
below.

---

## Step 3 — Generate Secrets

Run the secret generator locally (or on the server) to produce all
required cryptographic values:

```bash
cd /path/to/hybridsocial
cp .env.production.example .env
sh docker/generate-secrets.sh .env
```

This generates:
- `SECRET_KEY_BASE` — Phoenix session signing key
- `CROWDSEC_BOUNCER_CADDY_KEY` — shared secret between Caddy and CrowdSec
- `MESSAGE_ENCRYPTION_KEY` — encrypts DM content at rest
- `DATA_ENCRYPTION_KEY` — encrypts private keys, 2FA secrets, emails
- `INSTANCE_PUBLIC_KEY` / `INSTANCE_PRIVATE_KEY` — RSA keypair for the
  instance actor (federation signing)

**Back up the `.env` file immediately.** If you lose `DATA_ENCRYPTION_KEY`
or `MESSAGE_ENCRYPTION_KEY`, all encrypted DMs, private keys, 2FA secrets,
and emails become permanently unrecoverable.

---

## Step 4 — Configure Environment Variables

In Coolify's **Environment** tab for the resource, set every variable
from your generated `.env`. Coolify injects these into the Compose stack
at deploy time.

### Required

| Variable | Value |
|----------|-------|
| `DOMAIN` | `social.example.com` (your domain) |
| `DB_PASSWORD` | A strong random password |
| `SECRET_KEY_BASE` | (from generate-secrets.sh) |
| `DATA_ENCRYPTION_KEY` | (from generate-secrets.sh) |
| `MESSAGE_ENCRYPTION_KEY` | (from generate-secrets.sh) |
| `CROWDSEC_BOUNCER_CADDY_KEY` | (from generate-secrets.sh) |
| `INSTANCE_PUBLIC_KEY` | (from generate-secrets.sh, base64) |
| `INSTANCE_PRIVATE_KEY` | (from generate-secrets.sh, base64) |

### Recommended

| Variable | Value |
|----------|-------|
| `MEDIA_HOST` | `https://media.social.example.com` |
| `MEDIA_DOMAIN` | `media.social.example.com` |
| `TRUSTED_PROXIES` | `127.0.0.0/8` (default — see below) |
| `LOG_LEVEL` | `info` |
| `POOL_SIZE` | `10` (increase for high traffic) |

### `TRUSTED_PROXIES`

This is the CIDR range of the reverse proxy in front of the backend. The
`TrustedProxies` plug only honors `X-Forwarded-For` from IPs in this range
— it prevents client-side IP spoofing that would bypass IP bans.

- If Caddy and the backend are on the same Docker host (the default
  compose setup): `127.0.0.0/8` is correct — Docker's bridge network
  routes through the loopback range.
- If you have a separate proxy host: set it to that host's IP range,
  e.g. `10.0.0.0/8`.

### Email (optional but recommended)

Set these if you want email confirmations, password resets, and
CrowdSec ban-digest notifications:

| Variable | Value |
|----------|-------|
| `SMTP_HOST` | `smtp.your-provider.com` |
| `SMTP_PORT` | `587` |
| `SMTP_USER` | `your-smtp-user` |
| `SMTP_PASS` | `your-smtp-password` |
| `MAIL_FROM` | `noreply@social.example.com` |
| `CROWDSEC_NOTIFY_EMAIL_TO` | `admin@social.example.com` |

Alternatively, use Resend:

| Variable | Value |
|----------|-------|
| `RESEND_API_KEY` | `re_xxxxxxxxxxxx` |

If neither is set, emails are silently skipped and the local Swoosh
adapter is used (dev only).

### S3 Storage (optional)

By default uploads are stored on the local filesystem in the `uploads`
Docker volume. To use S3/R2 instead:

| Variable | Value |
|----------|-------|
| `S3_BUCKET` | `your-bucket-name` |
| `S3_REGION` | `us-east-1` |
| `S3_ACCESS_KEY_ID` | `your-access-key` |
| `S3_SECRET_ACCESS_KEY` | `your-secret-key` |
| `S3_ENDPOINT` | (leave empty for AWS; set for R2/MinIO) |

---

## Step 5 — Deploy

Click **Deploy** in Coolify. The first deploy will:

1. Build the `backend` image (Elixir release — takes ~3-5 min)
2. Build the `frontend` image (SvelteKit adapter-node — ~2-3 min)
3. Build the `caddy` image (custom Caddy with Coraza + CrowdSec + CF — ~2-3 min)
4. Start infrastructure (Postgres, Valkey, NATS, OpenSearch, ClamAV, CrowdSec)
5. Run `backend-migrate` (one-shot — creates schema)
6. Start `backend` and `frontend` once migrations succeed
7. Start `caddy` (begins serving traffic once CrowdSec is healthy)

Total first-deploy time: **10-15 minutes** depending on server speed.

ClamAV has a `start_period: 600s` (10 min) healthcheck because it pulls
virus signatures on first boot. Caddy won't proxy to the backend until
CrowdSec is healthy, so the site may take a few minutes to appear after
the containers are up.

---

## Step 6 — First-Run Setup

After the first successful deploy, run the database setup command. In
Coolify, open a terminal on the `backend` service (or SSH to the server
and exec into the container):

```bash
bin/hybridsocial eval "Hybridsocial.Release.setup()"
```

This runs migrations (if the one-shot container missed any) and seeds the
initial admin account + default settings.

### Log In and Configure

1. Visit `https://social.example.com`
2. Log in with the seeded admin credentials (check the seed output in the
   terminal — the password is printed once)
3. Go to **Admin → Settings** and configure:
   - Instance name and description
   - Registration mode (`open`, `approval`, or `closed`)
   - Character limit, upload limits, rate limits
   - Federation policies (allow/deny instances, MRF rules)
   - Email confirmation requirements

### Create Your Admin Password

The seed creates a temporary admin account. Change the password
immediately via **Settings → Security**.

---

## Step 7 — Verify the Deployment

Check each layer:

```bash
# Backend health
curl -s https://social.example.com/api/v1/instance | jq .

# Webfinger (federation entry point)
curl -s https://social.example.com/.well-known/webfinger?resource=acct:admin@social.example.com | jq .

# NodeInfo
curl -s https://social.example.com/nodeinfo/2.0 | jq .

# Actor document (federation)
curl -s -H "Accept: application/activity+json" https://social.example.com/actor | jq .

# Frontend loads
curl -s -o /dev/null -w "%{http_code}" https://social.example.com/
# Should return 200

# Media domain (if configured)
curl -s -o /dev/null -w "%{http_code}" https://media.social.example.com/uploads/
# Should return 200 or 404 (not 502)
```

If the frontend loads but API calls fail, check that Caddy is routing
`/api/*` to the backend container:

```bash
# Inside the caddy container
docker logs hs_caddy --tail 50
```

---

## Alternative: Behind Coolify's Proxy

If you can't free up ports 80/443 (because Coolify's own proxy is using
them for other apps), you can run HybridSocial without its own Caddy
layer. **You lose the WAF (Coraza/OWASP CRS), CrowdSec, and Cloudflare
IP integration** — the backend's own rate limiting and IP banning still
work, but you don't get application-layer attack filtering.

### Steps

1. Create a `docker-compose.coolify.yml` override that removes the
   `caddy`, `crowdsec`, and `clamav` services, and exposes the frontend
   and backend ports:

   ```yaml
   services:
     caddy:
       profiles: ["never"]
     crowdsec:
       profiles: ["never"]
     backend:
       ports:
         - "4000:4000"
     frontend:
       ports:
         - "3000:3000"
   ```

2. In Coolify, set the compose file to both files:
   ```
   docker-compose-production.yml:docker-compose.coolify.yml
   ```
   Or use Coolify's "Override Compose" field with the override above.

3. In Coolify's resource settings, set:
   - **Domain**: `https://social.example.com`
   - **Port**: `3000` (the SvelteKit frontend)
   - **Proxy**: enabled (Coolify's Traefik/Caddy handles TLS)

4. The SvelteKit frontend's `ORIGIN` must point to your domain. Set in
   the environment:
   ```
   ORIGIN=https://social.example.com
   ```

5. **Routing problem**: Without the project's Caddy, Coolify's proxy
   routes everything to one port (3000 = frontend). API calls to
   `/api/*` need to reach the backend (port 4000). You have two options:

   **Option A — SvelteKit hooks proxy**: Configure the frontend to
   proxy `/api/*` to `http://backend:4000` via a SvelteKit server hook.
   This requires a code change in `frontend/src/hooks.server.ts`.

   **Option B — Coolify custom routing**: If your Coolify supports
   custom Traefik labels, add path-based routing rules that send
   `/api/*`, `/.well-known/*`, `/inbox`, `/users/*`, `/actors/*`,
   `/nodeinfo/*` to port 4000, and everything else to port 3000.

**This alternative is significantly more complex and loses the security
stack. The recommended path is to use the full compose with the
project's Caddy on a server where ports 80/443 are available.**

---

## Managing Persistent Data

All stateful services use named Docker volumes. Coolify preserves these
across redeploys. To back them up:

```bash
# Database (most important)
docker exec hs_db pg_dump -U hybridsocial hybridsocial_prod > backup.sql

# Uploads (if using local storage)
docker cp hs_backend:/app/uploads ./uploads-backup

# Encryption keys — these are in your .env, NOT in a volume.
# If you lose DATA_ENCRYPTION_KEY or MESSAGE_ENCRYPTION_KEY,
# all encrypted data is unrecoverable.
```

---

## Updating

To update HybridSocial on Coolify:

1. `git pull` on your server (or trigger Coolify's Git webhook)
2. Click **Redeploy** in Coolify
3. The `backend-migrate` one-shot container runs new migrations before
   the backend restarts — zero-downtime for additive migrations
4. Breaking migrations may require brief downtime; check the migration
   files in `backend/priv/repo/migrations/` before deploying

---

## Troubleshooting

### Site returns 502

Caddy waits for CrowdSec to be healthy before starting. Check:

```bash
docker logs hs_crowdsec --tail 30
docker logs hs_caddy --tail 30
```

CrowdSec needs ~30 seconds to start its LAPI. Caddy has no explicit
healthcheck dependency on CrowdSec, but the `depends_on` condition is
`service_healthy` — so Caddy won't start until CrowdSec is ready.

### OpenSearch won't start (OOM)

OpenSearch is configured with `-Xms512m -Xmx512m`. If the host has less
than 4 GB RAM, reduce this in the compose:

```yaml
opensearch:
  environment:
    - "OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx256m"
```

### ClamAV taking forever

First boot downloads ~400 MB of virus signatures. The healthcheck has a
10-minute `start_period`. Don't worry — the backend still accepts uploads
(ClamAV scanning is fail-closed, meaning uploads are rejected if the
scanner is unreachable, but the scanner will be ready within minutes).

### Federation not working (remote instances can't fetch our actor)

Check that your domain resolves and the actor document is reachable:

```bash
curl -H "Accept: application/activity+json" https://social.example.com/actor
```

If Cloudflare is blocking federation traffic, check that the WAF in
Cloudflare's dashboard isn't returning challenges for `application/activity+json`
requests. You may need to add a WAF custom rule to skip challenges for
requests with `Accept: application/activity+json`.

### Database migrations failed

```bash
docker logs hs_migrate --tail 50
```

The `backend-migrate` container runs as a one-shot. If it fails, the
`backend` container won't start (it depends on
`service_completed_successfully`). Fix the migration issue, then redeploy.

---

## Security Checklist

After deployment, verify:

- [ ] `DATA_ENCRYPTION_KEY` and `MESSAGE_ENCRYPTION_KEY` are backed up
      somewhere safe (not in the repo, not on the same disk)
- [ ] Admin password has been changed from the seed default
- [ ] Registration mode is set appropriately (not `open` unless you
      intend public signups)
- [ ] `TRUSTED_PROXIES` matches your deployment topology
- [ ] Cloudflare SSL mode is set to **Full** (not Flexible, which leaks
      traffic between CF and origin)
- [ ] SMTP credentials are set (needed for password reset emails)
- [ ] Media is served from a separate domain (`MEDIA_HOST` is set)
- [ ] IP banning works (test: ban a test IP, verify access is blocked)
