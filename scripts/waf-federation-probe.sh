#!/usr/bin/env bash
# WAF federation probe.
#
# Fires a battery of realistic ActivityPub deliveries + API smoke
# tests against a running HybridSocial stack, then parses the
# Coraza audit log to print which (if any) CRS rules fired against
# legitimate traffic. Anything blocked here is a false positive
# that should be added to caddy/coraza/crs-tuning.conf.
#
# Usage:
#   scripts/waf-federation-probe.sh [HOST]
#
#   HOST defaults to https://localhost. The stack must be running
#   (docker compose -f docker-compose-production.yml up -d) and the
#   caddy container must be reachable. Self-signed TLS is OK — the
#   script uses curl -k.
#
# Exit codes:
#   0 — all probes returned a non-WAF status (200, 201, 202, 401,
#       403/404 from the application, etc.). The WAF didn't reject
#       anything that should be legitimate.
#   1 — at least one probe was blocked by Coraza (HTTP 403 with a
#       matching audit log entry). See the printed table.
#   2 — stack isn't reachable.

set -euo pipefail

HOST="${1:-https://localhost}"
CADDY_CONTAINER="${CADDY_CONTAINER:-hs_caddy}"
AUDIT_LOG_PATH="/var/log/caddy/coraza-audit.log"

# ANSI colors only when stdout is a TTY.
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_DIM=''; C_RST=''
fi

# Truncate the audit log on the caddy container so we only collect
# entries from this probe run. Best-effort — if the file doesn't
# exist yet the WAF hasn't blocked anything since last roll.
docker exec "$CADDY_CONTAINER" sh -c "echo > $AUDIT_LOG_PATH" 2>/dev/null \
  || echo "${C_DIM}note: couldn't truncate audit log (stack down? wrong container name?)${C_RST}"

# ---- Probe definitions ----
#
# Each probe is one curl invocation. We record the HTTP status and
# the URL; statuses ≥500 (Coraza phase:2 deny when ProcessPartial
# would otherwise mid-stream a response) and 403 with WAF audit log
# entry indicate a false positive.

declare -a PROBE_RESULTS=()

probe() {
  local name="$1" method="$2" path="$3" content_type="$4" body="${5:-}"

  local code
  code=$(
    curl -k -s -o /dev/null -w '%{http_code}' \
      -X "$method" \
      -H "Content-Type: $content_type" \
      -H "Accept: application/activity+json" \
      -H "User-Agent: HybridSocial-WAF-Probe/1.0" \
      ${body:+-d "$body"} \
      "$HOST$path"
  ) || code=000

  PROBE_RESULTS+=("$name|$method|$path|$code")

  if [ "$code" = "000" ]; then
    echo "${C_RED}✗${C_RST} $name → connection refused/timeout"
    return 1
  elif [ "$code" = "403" ]; then
    echo "${C_RED}✗${C_RST} $name → 403 (WAF or app)"
  elif [[ "$code" =~ ^5 ]]; then
    echo "${C_YEL}!${C_RST} $name → $code (server error)"
  else
    echo "${C_GRN}✓${C_RST} $name → $code"
  fi
}

# ---- Connectivity check ----
echo "Probing $HOST ..."
if ! curl -k -s -o /dev/null --max-time 5 "$HOST"; then
  echo "${C_RED}Stack unreachable at $HOST${C_RST}" >&2
  exit 2
fi

# ---- ActivityPub federation deliveries ----
# We fire unsigned bodies on purpose — the Phoenix layer rejects them
# with 401 (signature missing), but the WAF must let the bytes
# through to reach that point. Anything 403 here means CRS killed it.

AP_FOLLOW='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/follow-1","type":"Follow","actor":"https://remote.example/users/alice","object":"https://localhost/users/bob"}'

AP_CREATE_NOTE='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/create-1","type":"Create","actor":"https://remote.example/users/alice","object":{"type":"Note","id":"https://remote.example/notes/1","content":"<p>Hello federation</p>","attributedTo":"https://remote.example/users/alice","to":["https://localhost/users/bob"]}}'

AP_CREATE_ARTICLE='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/create-2","type":"Create","actor":"https://remote.example/users/alice","object":{"type":"Article","id":"https://remote.example/articles/1","name":"Long form post","content":"<h1>Article</h1><p>Body with code: <code>SELECT * FROM users</code> would normally trip CRS</p>","attributedTo":"https://remote.example/users/alice"}}'

AP_UPDATE='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/update-1","type":"Update","actor":"https://remote.example/users/alice","object":{"type":"Note","id":"https://remote.example/notes/1","content":"edited"}}'

AP_DELETE='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/delete-1","type":"Delete","actor":"https://remote.example/users/alice","object":"https://remote.example/notes/1"}'

AP_ANNOUNCE='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/announce-1","type":"Announce","actor":"https://remote.example/users/alice","object":"https://remote.example/notes/1"}'

AP_LIKE='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/like-1","type":"Like","actor":"https://remote.example/users/alice","object":"https://remote.example/notes/1"}'

AP_ACCEPT='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/accept-1","type":"Accept","actor":"https://remote.example/users/alice","object":"https://remote.example/activities/follow-1"}'

AP_REJECT='{"@context":"https://www.w3.org/ns/activitystreams","id":"https://remote.example/activities/reject-1","type":"Reject","actor":"https://remote.example/users/alice","object":"https://remote.example/activities/follow-1"}'

echo
echo "── ActivityPub deliveries ──"
probe "AP Follow"          POST /inbox application/activity+json "$AP_FOLLOW"
probe "AP Create Note"     POST /inbox application/activity+json "$AP_CREATE_NOTE"
probe "AP Create Article"  POST /inbox application/activity+json "$AP_CREATE_ARTICLE"
probe "AP Update"          POST /inbox application/activity+json "$AP_UPDATE"
probe "AP Delete"          POST /inbox application/activity+json "$AP_DELETE"
probe "AP Announce"        POST /inbox application/activity+json "$AP_ANNOUNCE"
probe "AP Like"            POST /inbox application/activity+json "$AP_LIKE"
probe "AP Accept"          POST /inbox application/activity+json "$AP_ACCEPT"
probe "AP Reject"          POST /inbox application/activity+json "$AP_REJECT"

# ---- Discovery / public read endpoints ----
echo
echo "── Discovery + public reads ──"
probe "WebFinger"          GET  "/.well-known/webfinger?resource=acct:bob@localhost" 'application/json'
probe "NodeInfo"           GET  /nodeinfo/2.0 'application/json'
probe "Actor lookup"       GET  /users/bob application/activity+json
probe "Outbox"             GET  /users/bob/outbox application/activity+json
probe "Followers"          GET  /users/bob/followers application/activity+json

# ---- API smoke tests (anonymous; expect 401, not WAF block) ----
echo
echo "── API smoke ──"
probe "Login (anon)"       POST /api/v1/auth/login application/json '{"email":"x@x.com","password":"x"}'
probe "Me (anon)"          GET  /api/v1/auth/me application/json
probe "Public timeline"    GET  /api/v1/timelines/public application/json

# ---- Audit log analysis ----
echo
echo "── Coraza audit log ──"
audit_raw=$(docker exec "$CADDY_CONTAINER" sh -c "cat $AUDIT_LOG_PATH 2>/dev/null || true")

if [ -z "$audit_raw" ]; then
  echo "${C_GRN}Coraza didn't block anything during this run.${C_RST}"
  WAF_BLOCKED=0
else
  # Pull out (rule_id, uri) from any [id "NNNN"] occurrence — the
  # serial audit log format puts each rule in a [...] block.
  echo "$audit_raw" \
    | grep -oE '\[id "[0-9]+"\]|\[uri "[^"]+"\]' \
    | paste - - \
    | sort | uniq -c | sort -rn \
    | awk 'BEGIN{print "Hits  Rule    Path"} {printf "%-5d %-7s %s\n", $1, $3, $5}' \
    | tr -d '"'

  WAF_BLOCKED=1
fi

# ---- Summary ----
echo
echo "── Summary ──"
echo "Probes total: ${#PROBE_RESULTS[@]}"

blocked_403=$(printf '%s\n' "${PROBE_RESULTS[@]}" | awk -F'|' '$4 == 403' | wc -l)
serverr=$(printf '%s\n' "${PROBE_RESULTS[@]}" | awk -F'|' '$4 ~ /^5/' | wc -l)
ok=$(printf '%s\n' "${PROBE_RESULTS[@]}" | awk -F'|' '$4 !~ /^5/ && $4 != 403' | wc -l)

echo "  ${C_GRN}OK / non-WAF${C_RST}: $ok"
echo "  ${C_RED}403 (likely WAF)${C_RST}: $blocked_403"
echo "  ${C_YEL}5xx${C_RST}: $serverr"

if [ "$WAF_BLOCKED" = "1" ] || [ "$blocked_403" -gt 0 ]; then
  echo
  echo "${C_RED}Federation traffic was blocked. Add exclusions to caddy/coraza/crs-tuning.conf and re-run.${C_RST}"
  exit 1
fi

echo "${C_GRN}All clear.${C_RST}"
