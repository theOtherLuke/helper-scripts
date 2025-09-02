#!/usr/bin/env bash

# pass device uuids, names, or serials as arguments in a space separated list
# uuids and serials can be partials
# this will cause those lines to be highlighted
arg=$@

printf "─────────────────────────────────────────────────────────────────\n"
printf "\e[1;31m # Drive Info\e[0m\n"
printf "─────────────────────────────────────────────────────────────────\n"

declare -A dev_by_uuid
declare -A serial_by_name

while read -r dev uuid; do
    if [[ ! -z $uuid ]]; then
        dev_by_uuid["$uuid"]="$dev"
    fi
done < <(lsblk -no PKNAME,PARTUUID)

while read -r dev serial; do
    serial_by_name["${dev}"]="$serial"
done < <(lsblk -ndo NAME,SERIAL)

while read -r pool; do
    echo -e "\e[1;33mPOOL - $pool\e[0m"
    while read -r path; do
        realdev=$(readlink -f "$path" 2>/dev/null || echo "$path")
        base=$(lsblk -no PKNAME "$realdev" 2>/dev/null)
        uuid="${path##*/}"
        serial="${serial_by_name[$base]}"
        # apply color to lines matching drive uuid, name, or serial
        c1=
        for a in "$@"; do
            [[ $uuid =~ $a ]] || [[ $a =~ $base ]] || [[ $serial =~ $a ]] && c1='\e[1;32m'
        done
        printf "${c1}%40s : %-5s : %-10s\e[0m\n" "$uuid" "$base" "$serial"
    done < <(zpool status -P "$pool" | awk ' $1=="config:" {conf=1; next} conf && $1=="errors:" {conf=0} conf && $1 ~ /^\/dev\// {print $1}')
    printf "─────────────────────────────────────────────────────────────────\n"
done < <(zpool list -H -o name)
printf "\n"
