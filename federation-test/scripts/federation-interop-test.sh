#!/usr/bin/env bash
# Bidirectional federation interop test between arab.place (HybridSocial)
# and mastodon.arab.place (Mastodon 4.3).
#
# What it checks:
#   1. WebFinger lookups in BOTH directions
#   2. Actor JSON fetch in BOTH directions (with content-type negotiation)
#   3. NodeInfo
#   4. HTTP signature header presence on actor responses (informational)
#
# Account assumptions:
#   * HybridSocial: an account with handle `tester` exists on arab.place.
#     Create via: docker compose ... exec hs_backend bin/hybridsocial eval ...
#   * Mastodon: an account with handle `tester` exists on
#     mastodon.arab.place (created by mastodon-first-time-setup.sh).
#
# Each step prints PASS / FAIL with the relevant response excerpt.
# Exits non-zero if anything fails so the script is CI-friendly.

set -u

HS_DOMAIN="${HS_DOMAIN:-arab.place}"
MASTODON_DOMAIN="${MASTODON_DOMAIN:-mastodon.arab.place}"
HS_USER="${HS_USER:-tester}"
MASTODON_USER="${MASTODON_USER:-tester}"

if [ -t 1 ]; then
  C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_GRN=''; C_RED=''; C_YEL=''; C_DIM=''; C_RST=''
fi

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"; local cmd="$2"; local expect="$3"
  local out
  out=$(eval "$cmd" 2>&1)
  if echo "$out" | grep -qE "$expect"; then
    echo "${C_GRN}✓${C_RST} $name"
    PASS=$((PASS + 1))
  else
    echo "${C_RED}✗${C_RST} $name"
    echo "${C_DIM}  expected match: /$expect/${C_RST}"
    echo "${C_DIM}  got: $(echo "$out" | head -c 200)${C_RST}"
    FAIL=$((FAIL + 1))
  fi
}

warn() {
  local name="$1"; local cmd="$2"; local expect="$3"
  local out
  out=$(eval "$cmd" 2>&1)
  if echo "$out" | grep -qE "$expect"; then
    echo "${C_GRN}✓${C_RST} $name"
    PASS=$((PASS + 1))
  else
    echo "${C_YEL}!${C_RST} $name (informational, not a hard failure)"
    echo "${C_DIM}  expected match: /$expect/${C_RST}"
    WARN=$((WARN + 1))
  fi
}

echo "── WebFinger discovery ──"
check "Mastodon WebFinger for $HS_USER@$HS_DOMAIN" \
  "curl -sS 'https://$MASTODON_DOMAIN/.well-known/webfinger?resource=acct:$HS_USER@$HS_DOMAIN'" \
  'subject.*acct:'

check "HybridSocial WebFinger for $MASTODON_USER@$MASTODON_DOMAIN" \
  "curl -sS 'https://$HS_DOMAIN/.well-known/webfinger?resource=acct:$MASTODON_USER@$MASTODON_DOMAIN'" \
  'subject.*acct:'

check "HybridSocial WebFinger self-lookup ($HS_USER@$HS_DOMAIN)" \
  "curl -sS 'https://$HS_DOMAIN/.well-known/webfinger?resource=acct:$HS_USER@$HS_DOMAIN'" \
  '"links"'

check "Mastodon WebFinger self-lookup ($MASTODON_USER@$MASTODON_DOMAIN)" \
  "curl -sS 'https://$MASTODON_DOMAIN/.well-known/webfinger?resource=acct:$MASTODON_USER@$MASTODON_DOMAIN'" \
  '"links"'

echo
echo "── Actor JSON (application/activity+json) ──"
check "HybridSocial actor returns Person + publicKey" \
  "curl -sS -H 'Accept: application/activity+json' 'https://$HS_DOMAIN/users/$HS_USER'" \
  '"type"\s*:\s*"Person".*publicKeyPem'

check "Mastodon actor returns Person + publicKey" \
  "curl -sS -H 'Accept: application/activity+json' 'https://$MASTODON_DOMAIN/users/$MASTODON_USER'" \
  '"type"\s*:\s*"Person".*publicKeyPem'

echo
echo "── Actor JSON (application/ld+json) — content-type negotiation ──"
check "HybridSocial actor honors application/ld+json Accept" \
  "curl -sS -i -H 'Accept: application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"' 'https://$HS_DOMAIN/users/$HS_USER'" \
  'content-type:.*application/ld\+json'

check "Mastodon actor honors application/ld+json Accept" \
  "curl -sS -i -H 'Accept: application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"' 'https://$MASTODON_DOMAIN/users/$MASTODON_USER'" \
  'content-type:.*application/(ld\+json|activity\+json)'

echo
echo "── @context shape (must be array per spec) ──"
check "HybridSocial actor @context is an array" \
  "curl -sS -H 'Accept: application/activity+json' 'https://$HS_DOMAIN/users/$HS_USER'" \
  '"@context"\s*:\s*\['

check "Mastodon actor @context is an array" \
  "curl -sS -H 'Accept: application/activity+json' 'https://$MASTODON_DOMAIN/users/$MASTODON_USER'" \
  '"@context"\s*:\s*\['

echo
echo "── NodeInfo discovery ──"
check "HybridSocial NodeInfo discovery" \
  "curl -sS 'https://$HS_DOMAIN/.well-known/nodeinfo'" \
  '"links"'

check "Mastodon NodeInfo discovery" \
  "curl -sS 'https://$MASTODON_DOMAIN/.well-known/nodeinfo'" \
  '"links"'

echo
echo "── Outbox ──"
check "HybridSocial outbox returns OrderedCollection" \
  "curl -sS -H 'Accept: application/activity+json' 'https://$HS_DOMAIN/users/$HS_USER/outbox'" \
  '"OrderedCollection"'

check "Mastodon outbox returns OrderedCollection" \
  "curl -sS -H 'Accept: application/activity+json' 'https://$MASTODON_DOMAIN/users/$MASTODON_USER/outbox'" \
  '"OrderedCollection"'

echo
echo "── Live federation handshake ──"
echo "${C_DIM}This part requires manual UI action — the protocol-only checks above${C_RST}"
echo "${C_DIM}prove the wire format works; a real Follow handshake exercises the${C_RST}"
echo "${C_DIM}signed delivery path which is hard to script without acting as a real${C_RST}"
echo "${C_DIM}AP client. From either UI:${C_RST}"
echo
echo "  1. Log into https://$HS_DOMAIN as @$HS_USER"
echo "  2. Search for @$MASTODON_USER@$MASTODON_DOMAIN"
echo "  3. Click Follow"
echo "  4. Log into https://$MASTODON_DOMAIN as @$MASTODON_USER"
echo "  5. Verify the follow request appears (or auto-accepts)"
echo "  6. Post from Mastodon, check it appears on the HybridSocial timeline"
echo "  7. Reverse: search from Mastodon for @$HS_USER@$HS_DOMAIN, follow, verify"

echo
echo "── Summary ──"
echo "  ${C_GRN}Passed:${C_RST} $PASS"
echo "  ${C_RED}Failed:${C_RST} $FAIL"
echo "  ${C_YEL}Warnings:${C_RST} $WARN"

exit $FAIL
