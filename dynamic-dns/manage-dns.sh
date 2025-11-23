#!/usr/bin/env bash
### for use with ddns-updater from : `https://github.com/qdm12/ddns-updater`

### COLORS
c_red=$(printf "\e[1;31m")
c_green=$(printf "\e[1;32m")
c_yellow=$(printf "\e[1;33m")
c_blue=$(printf "\e[1;34m")
c_purple=$(printf "\e[1;35m")
c_cyan=$(printf "\e[1;36m")
c_reset=$(printf "\e[0m")

### FORMATS
a_hdr="${c_red} %s${c_reset}\n"
m_hdr="${c_green}==== %s ====${c_reset}\n"
n_hdr="${c_cyan} %s ${c_reset}\n"
q_hdr="${c_green} %s${c_reset}"
i_hdr="${c_yellow} %20s : ${c_purple}%s${c_reset}\n"

config_file="$HOME/data/config.json"

declare -Ag hosts_list
declare -a key_order=(
    provider
    domain
    host
    api_key
    secret_api_key
    username
    password
    ip_version
    ipv6_suffix
)

query() {
    message="$@"
    printf "\e[s${c_cyan} %s ${c_reset}" "$message" >&2
    read -r answer
    printf "%s\n" "$answer"
}

query-reset() {
    printf "\e[u\e[J"
}

menuitem() {
    option_color=${c_cyan}
    item_color=${c_blue}
    option=$1
    item=$2
    printf "${option_color} %s) ${item_color}%s\n" "${option}" "${item}"
}

domain_root() {
    local domain="$1"
    domain="${domain#www.}"
    domain="${domain#mail.}"
    domain="${domain#api.}"
    domain="${domain#ftp.}"
    printf "%s" "$domain"
}

print-sorted-object() {
    local ref="$1"
    declare -n obj="$ref"

    # Known keys first
    for k in "${key_order[@]}"; do
        [[ -v obj[$k] ]] && printf "${i_hdr}" "$k" "${obj[$k]}"
    done

    # Unknown keys alphabetically
    local unknown=()
    for k in "${!obj[@]}"; do
        [[ ! " ${key_order[*]} " =~ " $k " ]] && unknown+=("$k")
    done

    if (( ${#unknown[@]} )); then
        printf "\e[2m--- extra keys ---\e[0m\n" >&2
        IFS=$'\n' sorted=($(sort <<<"${unknown[*]}"))
        unset IFS
        for k in "${sorted[@]}"; do
            printf "${i_hdr}" "$k" "${obj[$k]}" >&2
        done
    fi
}

rebuild-ddns-index() {
    sortable_keys=()
    for domain in "${!hosts_list[@]}"; do
        declare -n arr="${hosts_list[$domain]}"
        provider="${arr[provider]}"
        root=$(domain_root "$domain")
        sortable_keys+=("$provider|$root|$domain")
    done

    IFS=$'\n' sorted_keys=($(printf '%s\n' "${sortable_keys[@]}" | sort -t'|' -k1,1 -k2,2V -k3,3V))
    unset IFS
}

ddns-menu() {
    while :; do
        clear
        printf "${m_hdr}" "DDNS CONFIGURATION"

        for i in "${!sorted_keys[@]}"; do
            IFS='|' read -r provider root domain <<<"${sorted_keys[$i]}"
            menuitem "$((i+1))" "$domain ($provider)"
        done

        menuitem "a" "Add new entry"
        menuitem "s" "Save changes"
        menuitem "q" "Quit"

        choice="$(query "Select a domain or option")"

        case "$choice" in
            [1-9]*)
                idx=$((choice-1))
                if [[ idx -ge 0 && idx -lt ${#sorted_keys[@]} ]]; then
                    IFS='|' read -r provider root domain <<<"${sorted_keys[$idx]}"
                    ddns-entry-menu "$domain"
                else
                    query "Invalid selection, press enter to continue"
                fi
                ;;
            a|A) add-entry ;;
            s|S) export-json ;;
            q|Q) break ;;
            *) query "Invalid selection, press enter to continue" ;;
        esac
        rebuild-ddns-index
    done
}

ddns-entry-menu() {
    local domain="$1"
    declare -n arr="${hosts_list[$domain]}"

    while :; do
        clear
        printf "${m_hdr}" "EDIT DDNS ENTRY: $domain"

        menuitem "1" "Edit fields"
        menuitem "2" "Delete entry"
        menuitem "b" "<- Go Back"

        choice="$(query "Select an action")"

        case "$choice" in
            1) edit-entry "$domain" ;;
            2) delete-entry "$domain"; break ;;
            b|B) break ;;
            *) query "Invalid selection, press enter to continue" ;;
        esac
    done
}

edit-entry() {
    local domain="$1"
    declare -n arr="${hosts_list[$domain]}"

    while :; do
        clear
        printf "\e[1;33m%-40s\e[0m\n" "EDIT FIELDS: $domain"

        # Print current fields
        fields=("${!arr[@]}")
        for i in "${!fields[@]}"; do
            field="${fields[$i]}"
            menuitem "$((i+1))" "$field = ${arr[$field]}"
        done

        # Add special options
        menuitem "a" "Add new field"
        menuitem "d" "Delete a field"
        menuitem "b" "<- Go Back"

        choice="$(query "Select a field or action")"

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            # Edit existing field
            idx=$((choice-1))
            if (( idx >= 0 && idx < ${#fields[@]} )); then
                field="${fields[$idx]}"
                val="$(query "Enter new value for $field")"
                arr[$field]="$val"
            else
                query "Invalid selection, press enter to continue"
            fi

        elif [[ "$choice" =~ ^[aA]$ ]]; then
            # Add a new field from available key_order
            available_fields=()
            for k in "${key_order[@]}"; do
                [[ -v arr[$k] ]] || available_fields+=("$k")
            done
            if (( ${#available_fields[@]} == 0 )); then
                query "No additional fields available to add. Press enter to continue"
                continue
            fi

            for i in "${!available_fields[@]}"; do
                menuitem "$((i+1))" "${available_fields[$i]}"
            done
            sel="$(query "Select a field to add")"
            if [[ "$sel" =~ ^[0-9]+$ ]]; then
                idx=$((sel-1))
                if (( idx >= 0 && idx < ${#available_fields[@]} )); then
                    field="${available_fields[$idx]}"
                    val="$(query "Enter value for $field")"
                    arr[$field]="$val"
                else
                    query "Invalid selection, press enter to continue"
                fi
            fi

        elif [[ "$choice" =~ ^[dD]$ ]]; then
            # Delete a field
            deletable_fields=()
            for f in "${!arr[@]}"; do
                [[ "$f" != "domain" ]] && deletable_fields+=("$f")
            done
            if (( ${#deletable_fields[@]} == 0 )); then
                query "No fields available to delete. Press enter to continue"
                continue
            fi

            for i in "${!deletable_fields[@]}"; do
                menuitem "$((i+1))" "${deletable_fields[$i]}"
            done
            sel="$(query "Select a field to delete")"
            if [[ "$sel" =~ ^[0-9]+$ ]]; then
                idx=$((sel-1))
                if (( idx >= 0 && idx < ${#deletable_fields[@]} )); then
                    field="${deletable_fields[$idx]}"
                    unset "arr[$field]"
                    query "Deleted field '$field'. Press enter to continue"
                else
                    query "Invalid selection, press enter to continue"
                fi
            fi

        elif [[ "$choice" =~ ^[bB]$ ]]; then
            break
        else
            query "Invalid selection, press enter to continue"
        fi
    done
}


new_edit-entry() {
    local domain="$1"
    declare -n arr="${hosts_list[$domain]}"

    while :; do
        clear
        printf "${m_hdr}" "EDIT FIELDS: $domain"

        # List current fields
        fields=("${!arr[@]}")
        for i in "${!fields[@]}"; do
            field="${fields[$i]}"
            menuitem "$((i+1))" "$field = ${arr[$field]}"
        done

        # Option to add a new field
        menuitem "a" "Add new field"
        menuitem "b" "<- Go Back"

        choice="$(query "Select a field to edit or an option")"

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            idx=$((choice-1))
            [[ idx -ge 0 && idx -lt ${#fields[@]} ]] || { query "Invalid selection, press enter to continue"; continue; }
            field="${fields[$idx]}"
            val="$(query "Enter new value for $field")"
            arr[$field]="$val"

        elif [[ "$choice" =~ ^[aA]$ ]]; then
            # Add a new field
            available_fields=()
            for f in "${key_order[@]}"; do
                [[ ! -v arr[$f] ]] && available_fields+=("$f")
            done

            if (( ${#available_fields[@]} == 0 )); then
                query "All fields already exist. Press enter to continue."
                continue
            fi

            # Show menu of available fields
            clear
            printf "\e[1;33m%-40s\e[0m\n" "AVAILABLE FIELDS TO ADD"
            for i in "${!available_fields[@]}"; do
                menuitem "$((i+1))" "${available_fields[$i]}"
            done
            menuitem "b" "<- Go Back"

            field_choice="$(query "Select a field to add")"
            if [[ "$field_choice" =~ ^[0-9]+$ ]]; then
                idx=$((field_choice-1))
                [[ idx -ge 0 && idx -lt ${#available_fields[@]} ]] || { query "Invalid selection"; continue; }
                new_field="${available_fields[$idx]}"
                val="$(query "Enter value for $new_field")"
                arr[$new_field]="$val"
                export-json
            elif [[ "$field_choice" =~ ^[bB]$ ]]; then
                continue
            else
                query "Invalid selection, press enter to continue"
            fi

        elif [[ "$choice" =~ ^[bB]$ ]]; then
            break
        else
            query "Invalid selection, press enter to continue"
        fi
    done
}

old_edit-entry() {
    local domain="$1"
    declare -n arr="${hosts_list[$domain]}"

    while :; do
        clear
        printf "${m_hdr}" "EDIT FIELDS: $domain"

        fields=("${!arr[@]}")
        # Sort by key_order for display
        IFS=$'\n' fields_sorted=($(for k in "${key_order[@]}"; do [[ -v arr[$k] ]] && echo "$k"; done))
        unset IFS

        for i in "${!fields_sorted[@]}"; do
            field="${fields_sorted[$i]}"
            menuitem "$((i+1))" "$field = ${arr[$field]}"
        done
        menuitem "b" "<- Go Back"

        choice="$(query "Select a field to edit")"

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            idx=$((choice-1))
            [[ idx -ge 0 && idx -lt ${#fields_sorted[@]} ]] || { query "Invalid selection"; continue; }
            field="${fields_sorted[$idx]}"
            val="$(query "Enter new value for $field")"
            arr[$field]="$val"
        elif [[ "$choice" =~ ^[bB]$ ]]; then
            break
        else
            query "Invalid selection, press enter to continue"
        fi
    done
}

delete-entry() {
    local domain="$1"

    # Confirm deletion
    while confirm=$(query "Are you sure you want to delete '$domain'? [y/N]"); do
        confirm=${confirm:-n}
        case "$confirm" in
            y|Y) break ;;
            n|N) query "Deletion cancelled. Press enter to continue."; return ;;
        esac
        query-reset
    done

    arr_name="${hosts_list[$domain]}"
    unset "hosts_list[$domain]"
    unset "$arr_name"

    query "Deleted entry for '$domain'. Press enter to continue."
}

add-entry() {
    clear
    printf "${m_hdr}" "ADD NEW DDNS ENTRY"

    declare -A new_entry
    # show numbered list of key_order fields
    for i in "${!key_order[@]}"; do
        menuitem "$((i+1))" "${key_order[$i]}"
    done

    selections="$(query "Enter space-separated numbers of fields to add")"

    for n in $selections; do
        idx=$((n-1))
        [[ idx -ge 0 && idx -lt ${#key_order[@]} ]] || continue
        field="${key_order[$idx]}"
        val="$(query "Enter value for $field")"
        new_entry[$field]="$val"
    done

    if [[ -z "${new_entry[domain]:-}" ]]; then
        query "Domain is required. Entry not added."
        return
    fi

    arr_name="config_$(date +%s%N)"  # unique array name
    declare -Ag "$arr_name"
    declare -n cfg="$arr_name"

    for k in "${!new_entry[@]}"; do
        cfg[$k]="${new_entry[$k]}"
    done

    hosts_list["${new_entry[domain]}"]="$arr_name"

    query "Added entry for ${new_entry[domain]}. Press enter to continue."
}

export-json() {
    clear
    printf "${m_hdr}" 'SAVE '$config_file''
    local jq_objects=()

    # Build JSON objects from hosts_list
    for domain in "${!hosts_list[@]}"; do
        declare -n arr="${hosts_list[$domain]}"
        obj="{}"

        # Known keys first
        for k in "${key_order[@]}"; do
            [[ -v arr[$k] ]] && obj=$(jq --arg k "$k" --arg v "${arr[$k]}" '. + {($k): $v}' <<<"$obj")
        done

        # Extra keys
        for k in "${!arr[@]}"; do
            [[ ! " ${key_order[*]} " =~ " $k " ]] && obj=$(jq --arg k "$k" --arg v "${arr[$k]}" '. + {($k): $v}' <<<"$obj")
        done

        jq_objects+=("$obj")
    done

    # Combine into JSON array
    final_json=$(jq -n --argjson settings "$(jq -s '.' <<<"${jq_objects[@]}")" '{settings: $settings}')

    query '
     '${c_blue}'The next screen will show a preview of the JSON that will be saved to

        `'${c_green}$config_file${c_blue}'`

     Press '${c_yellow}'"Q" '${c_blue}'when you are done reviewing the JSON.

     '${c_cyan}'Press '${c_green}'ENTER'${c_cyan}' now to continue...'
    # Preview in terminal
    query-reset
    printf "$final_json" | batcat --language=json --file-name=$config_file --decorations=always --paging=always

    # Confirm save
    while confirm=$(query "Save JSON to $config_file? [y/N]"); do
        confirm=${confirm:-n}
        case "$confirm" in
            y|Y)
                echo "$final_json" > "$config_file"
                query "Saved JSON to $config_file. Press enter to continue."
                break
                ;;
            n|N)
                query "Save cancelled. Press enter to continue."
                break
                ;;
        esac
        query-reset
    done
}

count=$(jq '.settings | length' "$config_file")
for ((i=0; i<count; i++)); do
    arr_name="config_$i"
    declare -Ag "$arr_name"
    declare -n cfg="$arr_name"

    keys=$(jq -r ".settings[$i] | keys[]" "$config_file")
    for key in $keys; do
        val=$(jq -r ".settings[$i].$key" "$config_file")
        cfg[$key]="$val"
        [[ $key == "domain" ]] && hosts_list["$val"]="$arr_name"
    done
done

# Build initial index
rebuild-ddns-index

# Launch menu
ddns-menu
