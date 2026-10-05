#!/usr/bin/env bash
declare -A NICS
declare -a COL_WIDTHS=(0 0)

status_field() {
    case $1 in
        up)   code=$'\e[1;32m' ;;
        down) code=$'\e[1;31m' ;;
        *)    code=$'\e[1;33m' ;;
    esac
    printf '%s%s\e[0m' "$code" "$1"
}

for nic in /sys/class/net/*; do
    n="$(basename "$nic")"
    [[ "$n" =~ ^(eno|enp|ens|enx|eth|em|wlp|wlan|wlo) ]] || continue # only return physical NICs
    bdf="$(basename "$(readlink -f "$nic/device")")"
    [[ "$bdf" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]$ ]] || continue # only return devices with hardware ids
    NICS["$n"]="$bdf"
done

for nic in "${!NICS[@]}"; do
    (( ${#nic} > ${COL_WIDTHS[0]} )) && COL_WIDTHS[0]=${#nic}
    (( ${#NICS[$nic]} > ${COL_WIDTHS[1]} )) && COL_WIDTHS[1]=${#NICS[$nic]}
done

printf "\n\e[1;34m%-*s : %-*s : %s\e[0m\n" ${COL_WIDTHS[0]} "DEVICE" ${COL_WIDTHS[1]} "HARDWARE ID" "STATE"

for nic in "${!NICS[@]}"; do
    status=$(status_field "$(cat "/sys/class/net/${nic}/operstate" 2>/dev/null || echo unknown)")
    printf "%-*s : %-*s : %s\n" ${COL_WIDTHS[0]} "$nic" ${COL_WIDTHS[1]} "${NICS[$nic]}" "$status"
done | sort

printf '\n'
