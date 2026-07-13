#!/usr/bin/env bash
set -euo pipefail

DOMAIN="$1"

NPM_ROOT="${2:-/opt/nginx-proxy-manager/letsencrypt/live}"

find_cert() {
    local cert

    for cert in "$NPM_ROOT"/npm-*/fullchain.pem; do
        [[ -f "$cert" ]] || continue
        if openssl x509 -in "$cert" -noout -ext subjectAltName |
            tr ',' '\n' |
            sed 's/^ *//' |
            awk -v d="DNS:$DOMAIN" '$0 == d { found=1 } END { exit !found }'
        then
            printf "%s" "$cert"
            return 0
        fi

    done

    return 1
}

CERT=$(find_cert) || {
    printf "\e[1;31mNo NPM certificate found for \e[1;33m%s\e[0m\n" "$DOMAIN"
    exit 1
}

printf "Found cert for \e[1;32m%s \e[0m: \e[1;35m%s\e[0m\n" "$DOMAIN" "$CERT"
exit
