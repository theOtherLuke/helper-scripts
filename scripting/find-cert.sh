#!/usr/bin/env bash
set -euo pipefail
cleanup() {
    trap - EXIT TERM INT
    printf '\e[0m'
    exit
}
trap cleanup EXIT TERM INT
if [[ -z ${1:-} ]]; then
    printf "%s\n" "Missing argument."
    exit 1
fi

DOMAIN="$1"
WARN_DAYS=30
WARN_SECONDS=$((WARN_DAYS * 86400))
NOW=$(date +%s)
NPM_ROOT="${2:-/opt/nginx-proxy-manager/letsencrypt/live}"

find_cert() {
    local cert
    local expires
    local date

    for cert in "$NPM_ROOT"/npm-*/fullchain.pem; do
        [[ -f "$cert" ]] || continue

        if openssl x509 -in "$cert" -noout -ext subjectAltName |
            tr ',' '\n' |
            sed 's/^ *//' |
            grep -Fxq "DNS:$DOMAIN"
        then
            expires=$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)
            date=$(date -d "$expires" +%s)

            printf "%s,%s,%s\n" "$cert" "$expires" "$date"
        fi
    done
}

status_color() {
    local remaining
    remaining=$(($1-NOW))
    if (( remaining <= 0 )); then
        printf $'\e[1;31m'
    elif (( remaining <= WARN_SECONDS )); then
        printf $'\e[1;33m'
    else
        printf $'\e[1;32m'
    fi
}

printf "\n\e[1;34m%s\e[0m\n\n" "Checking for certs for $DOMAIN"

found=false

while IFS="," read -r cert expires epoch; do
    found=true
    printf "Found certificate for \e[1;33m%s\e[0m\n" "$DOMAIN"
    expired_color="$(status_color "$epoch")"
    days=$(( (epoch - NOW) / 86400))
    printf "Expires: ${expired_color}%s ( %s days )\e[0m\n" "$expires" "$days"
    printf "Path: \e[1;36m%s\e[0m\n\n" "$cert"
done < <(find_cert)

if ! $found; then
    printf "\e[1;31mNo certs found for \e[1;33m%s\e[0m\n\n" "$DOMAIN"
fi
exit
