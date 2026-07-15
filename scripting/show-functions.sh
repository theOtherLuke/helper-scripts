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

cleanup() {
    trap - EXIT TERM INT
    printf '\e[?1049l\e[?25h\e[0m'
    set +x
    exit
}

trap cleanup EXIT TERM INT
#set -x
printf '\e[?1049h\e[?25l'
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
output_mode=0                # ← new variable

while [[ $# -gt 0 && "$1" =~ ^- ]]; do   # loop while we still have options
    case "$1" in
        -s|--simple)
            simple_mode=1
            shift
            ;;
        -o|--output)
            # make sure the next word exists and is *not* another option
            output_mode=1
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

# -----------------------------------------------------------------
# the remaining positional argument must be the script we want to scan
if [[ -z $1 ]]; then
    printf "${c_red}No script name specified.${c_reset}\n"
    usage
    exit 1
fi

script=$1                     # we already know it exists (checked later)
shift                         # discard it – any extra args are ignored on purpose
# -----------------------------------------------------------------

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

    if (( output_mode )); then
        # Build the filename from the function name and add .sh
        out_file="${selected_function}.sh"

        # Optional: ask before overwriting an existing file
        if [[ -e $out_file ]]; then
            printf "${c_yellow}File %s already exists. Overwrite? [y/N] ${c_reset}" "$out_file"
            read -r answer
            case "$answer" in
                y|Y) ;;                     # proceed
                *)   printf "Aborted.\n"; continue 2   # go back to the selection menu
            esac
        fi
    fi

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

    # Step 5: Show (and possibly write) the function
    bat_cmd=(stdbuf -oL batcat)

    if (( simple_mode )); then
        bat_cmd+=( -p --paging=never --line-range "$start_line":"$end_line" )
    else
        bat_cmd+=( --style=full --paging=never --line-range "$start_line":"$end_line" )
    fi

    bat_cmd+=("$script")

    if (( output_mode )); then
        # Write to the automatically‑named file; also show on screen with tee.
        "${bat_cmd[@]}" | tee "$out_file"
        printf "${c_green}Function %s written to %s${c_reset}\n" \
               "$selected_function" "$out_file"
    else
        # Normal behaviour – just print to terminal
        "${bat_cmd[@]}"
    fi

    message="Do you want to see another function?"
    default_choice="n"
    case "$default_choice" in y) default="[Y|n]";; n) default="[y|N]";; esac
    while printf "\e[s${c_purple}%s ${default}${c_reset}" "$message" && read -r yn; do
        yn=${yn:-$default_choice}
        [[ $yn =~ ^(y|Y)$ ]] && break || [[ $yn =~ ^(n|N)$ ]] && exit 0 || printf "\e[u\r\e[K"
    done

done
