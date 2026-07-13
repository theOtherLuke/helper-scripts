#!/usr/bin/env bash
set -euo pipefail
# set -x
cleanup() {
    trap - EXIT TERM INT
    set +x
    exit
}
trap cleanup EXIT TERM INT

if [[ -z ${1:-} ]]; then
    printf "ERROR: \n%s\n\n" "No domain provided."
    exit 1
fi

DOMAIN="$1"

NPM_ROOT="${2:-/opt/nginx-proxy-manager/letsencrypt/live}"
MAILCOW_SSL="/opt/mailcow-dockerized/data/assets/ssl"
MAILCOW_DIR="/opt/mailcow-dockerized"

log() {
    message="$@"
    printf "[ %s ] %s\n" "$(date '+%F %T')" "$message"
}

find_cert() {
    local cert
    local newest=""
    local newest_date=0
    local date

    for cert in "$NPM_ROOT"/npm-*/fullchain.pem; do
        [[ -f "$cert" ]] || continue

        if openssl x509 -in "$cert" -noout -ext subjectAltName |
            tr ',' '\n' |
            sed 's/^ *//' |
            grep -Fxq "DNS:$DOMAIN"
        then
            date=$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)
            date=$(date -d "$date" +%s)

            if (( date > newest_date )); then
                newest_date=$date
                newest=$cert
            fi
        fi
    done

    [[ -n "$newest" ]] && printf "%s" "$newest"
}

log "Checking for updated certs for $DOMAIN..."

CERT=$(find_cert) || {
    log "No NPM certificate found for $DOMAIN"
    exit 1
}

KEY="${CERT%/*}/privkey.pem"

if [[ ! -f "$KEY" ]]; then
    log "Private key not found: $KEY"
    exit 1
fi

NEW_FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256)
OLD_FP=$(openssl x509 \
    -in "$MAILCOW_SSL/cert.pem" \
    -noout -fingerprint -sha256 2>/dev/null || true)

if [[ "$NEW_FP" == "$OLD_FP" ]]; then
    log "Cert unchanged."
    exit 0
fi

log "New cert detected."

log "Updating Mailcow certificate..."

install -m 644 "$CERT" "$MAILCOW_SSL/cert.pem"
install -m 600 "$KEY" "$MAILCOW_SSL/key.pem"

cd "$MAILCOW_DIR"
log "Restarting:"

docker compose restart \
    dovecot-mailcow \
    postfix-mailcow

log "Mailcow certificate updated."
exit 0
