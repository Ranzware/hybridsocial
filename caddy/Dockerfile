# Custom Caddy image for HybridSocial production:
#   - Coraza WAF (OWASP CRS v4) for app-layer attack filtering
#   - CrowdSec bouncer for behavioral IP-level blocking
#
# CRS rules are baked into the image so the running container needs
# no internet access at startup. Bump CRS_VERSION to upgrade.

ARG CADDY_VERSION=2
ARG CRS_VERSION=v4.7.0

FROM caddy:${CADDY_VERSION}-builder AS builder
ENV GOTOOLCHAIN=auto
RUN xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http

FROM caddy:${CADDY_VERSION}-alpine
ARG CRS_VERSION

RUN apk add --no-cache curl ca-certificates && \
    mkdir -p /etc/caddy/coraza && \
    curl -fsSL "https://github.com/coreruleset/coreruleset/archive/refs/tags/${CRS_VERSION}.tar.gz" \
        -o /tmp/crs.tar.gz && \
    tar -xzf /tmp/crs.tar.gz -C /tmp && \
    mv /tmp/coreruleset-*/rules /etc/caddy/coraza/rules && \
    cp /tmp/coreruleset-*/crs-setup.conf.example /etc/caddy/coraza/crs-setup.conf && \
    rm -rf /tmp/crs.tar.gz /tmp/coreruleset-* && \
    apk del curl && \
    mkdir -p /var/log/caddy /tmp/coraza

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY coraza/coraza.conf /etc/caddy/coraza/coraza.conf
COPY coraza/crs-tuning.conf /etc/caddy/coraza/crs-tuning.conf
COPY waf.caddy /etc/caddy/waf.caddy
