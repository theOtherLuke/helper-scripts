#!/usr/bin/env bash

config_file="$HOME/.ssh/config"

while getopts "a" opt; do
    if [[ $opt =~ a ]]; then
        awk '
            tolower($1) == "host" { print $2 }
        ' "$config_file" && exit 0 || exit 1
    else
        cat << EOF
Usage: $0 [options]

Options:
    -a      Show only alias names
EOF
        exit 1
    fi
done

colors=(
    "\e[1;31m"
    "\e[1;32m"
    "\e[1;33m"
    "\e[1;34m"
    "\e[1;35m"
    "\e[1;36m"
)
reset="\e[0m"


if [[ ! -f "$config_file" ]]; then
    printf "\e[1;31m%s\e[0m" "$config not found."
    exit 1
fi

printf '\e[1m\n'
printf "%-20s | %-20s | %-20s\n" " ALIAS" " USER" " HOST"
printf "%-20s | %-20s | %-20s\n" "-------" "------" "------"

mapfile -t entries < <(
    awk '
        tolower($1) == "host" {
            # print previous block
            if (alias && host && user) {
                printf "%s %s %s\n", alias, user, host
            }
            alias = $2; host = ""; user = ""
        }

        tolower($1) == "hostname" { host=$2; next }
        tolower($1) == "user"     { user=$2; next }

        END {
            if (alias && host && user) {
                printf "%s %s %s\n", alias, user, host
            }
        }
    ' "$config_file"
)

i=0
old_color=
color=
for entry in "${entries[@]}"; do
    while :; do
        color=${colors[$((0 + $RANDOM % ${#colors[@]}))]}
        [[ $color != $old_color ]] && break
    done
    old_color=$color
    printf "${color}%-20s | %-20s | %-20s${reset}\n" $entry
    ((i++))
done
