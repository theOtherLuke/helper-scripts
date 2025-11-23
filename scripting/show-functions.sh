#!/usr/bin/env bash
### show-function.sh
## Parses a shell script for functions and asks the user to choose a function.
## Then, this script displays the selected function using `bat` for line numbers
## and syntax highlighting. cat may be substituted, but you will lose those
## features. line numbers may be turned off using the `-s|--simple` flag.


# COLORS: these have to be processed this way because many of my systems have
# an override for `cat` that uses `bat` (batcat) under the hood and bat seems
# to not like placing escape sequences directly in the heredoc the normal way
c_red=$(printf "\e[1;31m")
c_green=$(printf "\e[1;32m")
c_yellow=$(printf "\e[1;33m")
c_blue=$(printf "\e[1;34m")
c_purple=$(printf "\e[1;35m")
c_cyan=$(printf "\e[1;36m")
c_reset=$(printf "\e[0m")

usage() {
    cat <<EOF

${c_blue}Usage:${c_reset}
    show-function.sh [OPTIONS] <script_name>

${c_blue}Arguments:${c_reset}
    script_name          Name of the script to list and display functions from.

${c_blue}Options:${c_reset}
    -s, --simple         Simple mode: show function with minimal decorations
    -h, --help           Show this help message and exit

${c_blue}Examples:${c_reset}
    ./show-function.sh my_script.sh
    ./show-function.sh -s my_script.sh

EOF
}

# --- Step 0: Parse flags ---
simple_mode=0
while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -s|--simple)
            simple_mode=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf "${c_red}Unknown option:${c_reset} %s\n" "$1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z $1 ]]; then
    printf "${c_red}No script name specified.${c_reset}\n"
    usage
    exit 1
fi

if [[ -n $1 ]]; then
    if [[ -f $1 ]]; then
        script="$1"
    else
        printf "${c_red}Invalid filename :${c_reset} %s\n\n" "$1"
        usage
        exit 1
    fi
fi

# Step 1: Parse function names
mapfile -t functions < <(
    while read -r line; do
        if [[ ${line} =~ ^([A-Za-z0-9_-]+)\(\) ]]; then
            line="${BASH_REMATCH[1]}"
            echo "$line"
        fi
    done < "$script"
)

# Step 2: Present functions
while :; do
    clear
    echo "Available functions in $script:"
    for i in "${!functions[@]}"; do
        printf "${c_cyan}%3d) ${c_purple}%s${c_reset}\n" "$((i+1))" "${functions[$i]}"
    done
    printf "${c_cyan}%3s) ${c_purple}%s${c_reset}\n\n" "q" "QUIT"

    # Step 3: Ask user to select a function
    while printf "\e[s${c_blue}%s ${c_reset}" "Enter the number of the function to display: " && read -r choice; do

        # Validate choice
        [[ $choice =~ ^(q|Q)$ ]] && exit 0
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#functions[@]} )); then
            printf "\e[u\r\e[K"
            continue
        fi
        break
    done

    selected_function="${functions[$((choice-1))]}"

    # Step 4: Find line numbers of function
    read -r start_line end_line < <(
        awk -v fname="$selected_function" '
        $0 ~ fname"\\(\\)" {inside=1; brace_count=0; start=NR}
        inside {
            n_open = gsub(/{/, "{")
            n_close = gsub(/}/, "}")
            brace_count += n_open - n_close
            if (brace_count <= 0 && /}/) {print start, NR; exit}
        }
        ' "$script"
    )

    # Step 5: Display function using bat
    [[ $simple_mode -eq 1 ]] && stdbuf -oL batcat -p --paging=never --line-range "$start_line":"$end_line" "$script" || stdbuf -oL batcat --style=full --paging=never --line-range "$start_line":"$end_line" "$script"

    message="Do you want to see another function?"
    default_choice="n"
    case "$default_choice" in y) default="[Y|n]";; n) default="[y|N]";; esac
    while printf "\e[s${c_purple}%s ${default}${c_reset}" "$message" && read -r yn; do
        yn=${yn:-$default_choice}
        [[ $yn =~ ^(y|Y)$ ]] && break || [[ $yn =~ ^(n|N)$ ]] && exit 0 || printf "\e[u\r\e[K"
    done
done
