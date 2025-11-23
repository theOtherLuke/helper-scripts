#!/usr/bin/env bash

### COLORS
c_red="\e[1;31m"
c_green="\e[1;32m"
c_yellow="\e[1;33m"
c_blue="\e[1;34m"
c_purple="\e[1;35m"
c_cyan="\e[1;36m"
c_reset="\e[0m"

### VARIABLES
a_hdr="${c_red} %s${c_reset}\n"                      # alert format
m_hdr="${c_green}==== %s ====${c_reset}\n"           # menu header format
n_hdr="${c_cyan} %s ${c_reset}\n"                    # notify format
q_hdr="${c_green} %s${c_reset}"                      # query format
i_hdr="${c_yellow} %20s : ${c_purple}%s${c_reset}\n" # item format

### FUNCTIONS
main-menu() {
    while :; do
        clear
        printf "${m_hdr}" "MAIN MENU"
        menuitem "1" "Manage keys"
        menuitem "2" "Manage aliases"
        menuitem "3" "Add credentials (alias, host key, client key)"
        menuitem "4" "Remove credentials (alias, host key, client key)"
        menuitem "5" "Enable password authentication on remote host"
        menuitem "6" "Disable password authentication on remote host"
        menuitem "q" "Quit"
        # get user input
        case "$(query "Make a selection")" in
            1) manage-keys;;
            2) manage-aliases;;
            3) create-creds;;
            4) remove-creds;;
            5) enable-password-login;;
            6) disable-password-login;;
            q|Q) exit 0 ;;
        esac
    done
}

manage-keys() {
    while :; do
        clear
        printf "${m_hdr}" "MANAGE KEYS"
        menuitem "1" "Create key"
        menuitem "2" "Delete key"
        menuitem "3" "Add key to remote host"
        menuitem "4" "Remove key from remote host"
        menuitem "q" "<-Go Back"
        case "$(query "Make a selection")" in
            1) create-key; break ;;
            2) delete-key; break ;;
            3) add-key; break ;;
            4) remove-key; break ;;
            q|Q) return 0 ;;
        esac
    done
}

manage-aliases() {
    while :; do
        clear
        printf "${m_hdr}" "MANAGE KEYS"
        menuitem "1" "Create alias"
        menuitem "2" "Delete alias"
        menuitem "q" "<-Go Back"
        case "$(query "Make a selection")" in
            1) create-alias;;
            2) delete-alias;;
            q|Q) return 0 ;;
        esac
    done
}

create-creds() {
    printf "${m_hdr}" "Create SSH Credentials"
    create-key
    create-alias
    while :; do
        case "$(query "Disable password login?")" in
            y|Y) disable-password-login; break;;
            n|N) break;;
        esac
        query-reset
    done
}

remove-creds() {
    printf "${m_hdr}" "Remove SSH Credentials"
    while :; do
        case "$(query "Enable password login?")" in
            y|Y) enable-password-login; break;;
            n|N) break;;
        esac
        query-reset
    done
    remove-key
    delete-key
    delete-alias
}

create-key() {
    clear
    printf "${m_hdr}" "CREATE SSH KEY"

    # Ask for alias
    while :; do
        rem_alias="$(query "Enter alias (short name)")"
        rem_alias="${rem_alias,,}"
        rem_alias="${rem_alias//[[:space:]]/}"

        if [[ -z "$rem_alias" ]]; then
            printf "${c_red}Alias cannot be empty.${c_reset}\n"
            query "Press ENTER to continue..."
            query-reset
            continue
        fi

        if [[ "$rem_alias" =~ [^a-z0-9._-] ]]; then
            printf "${c_red}Invalid characters. Allowed: a–z 0–9 . _ -${c_reset}\n"
            query "Press ENTER to continue..."
            query-reset
            continue
        fi

        break
    done

    # Ask for username (optional)
    remote_user="$(query "Remote username (blank allowed)")"

    # Build paths
    key_path="$HOME/.ssh/${rem_alias}_ed25519"
    pub_path="${key_path}.pub"

    printf "\n${c_blue}Key will be created as:${c_reset}\n"
    printf "  ${c_green}%s${c_reset}\n" "$key_path"
    printf "  ${c_green}%s${c_reset}\n" "$pub_path"

    # Check existing key
    if [[ -f "$key_path" ]]; then
        printf "\n${c_yellow}Key already exists!${c_reset}\n"
        choice="$(query "Overwrite existing key? [y|N] ")"
        choice="${choice:-n}"
        case "$choice" in
            y|Y) printf "${c_yellow}Overwriting...${c_reset}\n"
                rm -f "${key_path}" "${pub_path}" ;;
            n|N) printf "${c_red}Cancelled.${c_reset}\n"; return 1 ;;
        esac
    fi

    key_algo="ed25519"

    printf "\n${c_green}Generating SSH keypair...${c_reset}\n"

    if ! ssh-keygen -t $key_algo -f "$key_path" -C "$rem_alias" -N ""; then
        printf "${c_red}Error: ssh-keygen failed.${c_reset}\n"
        return 1
    fi

    printf "\n${c_green}Key created successfully!${c_reset}\n"
    printf "${c_green}Private:${c_reset} %s\n" "$key_path"
    printf "${c_green}Public :${c_reset} %s\n" "$pub_path"

    # Export context for create-creds
    export rem_alias key_path pub_path remote_user

    query "Press ENTER to continue..."
}

delete-key() {
    printf "${m_hdr}" "Delete SSH Key"
    local ssh_dir="$HOME/.ssh"
    local -a keys=()

    # Enumerate all keys in ~/.ssh
    for file in $HOME/.ssh/*; do
        base="${file%.*}"

        # Check if private key exists AND corresponding .pub exists
        if [[ -f "$base" && -f "$base.pub" ]]; then
          keys+=("$(basename "$base")")
        fi
    done

    # No keys found?
    if (( ${#keys[@]} == 0 )); then
    printf "\nNo SSH keypairs found in %s\n" "$ssh_dir"
    read -rp "Press enter..." _
    return 1
    fi

    # Menu
    while :; do
        clear
        printf "${m_hdr}" "Delete SSH Key"
        printf "${m_hdr}" "Available SSH Keys"
        local i=1
        for key in "${keys[@]}"; do
            menuitem "$i" "$key"
            ((i++))
        done
        menuitem "q" "<-Back"

        choice="$(query "Select a key")"

        # Validate numeric choice
        if ! [[ $choice =~ ^[0-9]+$ ]] || (( choice < 0 || choice > ${#keys[@]} )); then
            if [[ $choice =~ (q|Q) ]]; then
                return 0
            else
                query-reset
                continue
            fi
        elif [[ $choice =~ ^[0-9]+$ ]]; then
            break
        fi
    done

    local selected="${keys[choice-1]}"
    local priv="$ssh_dir/$selected"
    local pub="$ssh_dir/$selected.pub"

    printf "\n\e[1;34mYou selected:\e[1;36m %s\e[0m\n" "$selected"
    printf "\n\e[1;34mSummary of files to be removed:\n"
    printf "\e[1;34m  -\e[1;33m %s\e[0m\n" "$priv"
    printf "\e[1;34m  -\e[1;33m %s\e[0m\n" "$pub"
    while :; do
        confirm=$(query "Are you sure you want to delete this keypair? [y|N] : ")
        confirm="${confirm:-n}"
        if [[ $confirm =~ (y|Y|n|N) ]]; then
            case "$confirm" in
            y|Y)
                rm -f "$priv" "$pub"
                printf "\nKeypair '%s' deleted.\n" "$selected"
                query "Press ENTER to continue..."
                return 0
                ;;
            n|N)
                printf "\nDeletion cancelled.\n"
                query "Press ENTER to continue..."
                return 0
                ;;
            esac
        fi
        query-reset
    done
}

create-alias() {
    printf "${m_hdr}" "Create SSH alias"

    # Select key
    keys=( ~/.ssh/*.pub )

    if [ ${#keys[@]} -eq 0 ]; then
        printf "No public keys found in ~/.ssh\n" >&2
        query "Press ENTER to return..."
        return
    fi

    clear
    printf "${m_hdr}" "Create SSH alias"
    i=1
    for k in "${keys[@]}"; do
        menuitem "${i}" "$(basename "$k" .pub)"
        i=$((i+1))
    done
    menuitem "q" "<-Cancel and return"

    while :; do
        choice=$(query "Make a selection : ")

        if [[ "$choice" =~ ^[qQ]$ ]]; then
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#keys[@]} ]; then
            sel_index=$((choice-1))
            pubkey_path="${keys[$sel_index]}"
            key_path="${pubkey_path%.pub}"
            key_choice=$(basename $pubkey_path)
            break
        fi
        query-reset
    done

    # derive alias from key name
    alias_name="${key_choice%%_*}"

    printf "${i_hdr}\n\n" "Using alias name" "$alias_name"

    # check ~/.ssh/config for existing alias
    exist_user=""
    exist_host=""

    if grep -q "^Host[[:space:]]\+$alias_name\$" ~/.ssh/config 2>/dev/null; then
        exist_user=$(awk -v a="$alias_name" '
            $1=="Host" && $2==a {found=1}
            found && $1=="User" {print $2; found=0}
        ' ~/.ssh/config)

        exist_host=$(awk -v a="$alias_name" '
            $1=="Host" && $2==a {found=1}
            found && ($1=="HostName"||$1=="Hostname") {print $2; found=0}
        ' ~/.ssh/config)
    fi

    # request username and hostname/endpoint if missing
    if [ -z "$exist_user" ]; then
        ssh_user=$(query "Enter remote host username : ")
    else
        ssh_user="$exist_user"
    fi

    if [ -z "$exist_host" ]; then
        while :; do
            ssh_host=$(query "Enter remote host endpoint (IP or hostname) : ")
            if [[ -n $ssh_host ]]; then
                break
            fi
            query-reset
        done
    else
        ssh_host="$exist_host"
    fi

    # review alias block
    printf "${n_hdr}" "Alias will be created as follows:"
    printf "${i_hdr}" "Host" "$alias_name"
    printf "${i_hdr}" "    HostName" "$ssh_host"
    printf "${i_hdr}" "    User" "$ssh_user"
    printf "${i_hdr}" "    IdentityFile" "$key_path"

    while :; do
        confirm=$(query "Write this alias to ~/.ssh/config? [Y|n] ")
        confirm=${confirm:-y}

        if [[ $confirm =~ (n|N) ]]; then
            printf "${a_hdr}" "Cancelled."
            query "Press ENTER to return..."
            return
        fi

        if [[ $confirm =~ (y|Y) ]]; then

            config_file="$HOME/.ssh/config"

            # check if alias exists
            if grep -qiE "^[[:space:]]*Host[[:space:]]+$alias_name(\s|$)" "$config_file"; then
                printf "${c_yellow}Alias '%s' already exists in ~/.ssh/config.${c_reset}\n" "$alias_name"

                # Show existing block
                printf "${c_blue}Existing block:${c_reset}\n"
                printf "${m_hdr}" ""
                sed -n "/^[[:space:]]*Host[[:space:]]\+$alias_name/,/^[[:space:]]*Host[[:space:]]/p" "$config_file" \
                    | sed '$d'
                printf "${m_hdr}" ""

                overwrite=$(query "Overwrite/update this alias? [Y|n] ")
                overwrite=${overwrite:-y}

                if [[ $overwrite =~ (n|N) ]]; then
                    printf "${c_red}Cancelled. Alias not modified.${c_reset}\n"
                    query "Press ENTER to return..."
                    return
                fi

                # delete existing alias
                tmpf=$(mktemp)
                awk -v alias="$alias_name" '
                    BEGIN {drop=0}
                    /^Host[[:space:]]+/ {
                        if ($2 == alias) {drop=1; next}
                        else drop=0
                    }
                    drop==0 {print}
                ' "$config_file" > "$tmpf"

                mv "$tmpf" "$config_file"
            fi

            # write new alias
            {
                printf "\nHost %s\n" "$alias_name"
                printf "    HostName %s\n" "$ssh_host"
                printf "    User %s\n" "$ssh_user"
                printf "    IdentityFile %s\n" "$key_path"
                printf "    IdentitiesOnly yes\n"
                printf "    # UPDATE=yes\n"
            } >> "$config_file"

            printf "${n_hdr}" "Alias written successfully."
            query "Press ENTER to continue..."
            break
        fi

        query-reset
    done

    # test alias
    printf "${n_hdr}" "Testing alias: ssh $alias_name"
    printf "${n_hdr}" "If password is required, enter it normally."

    ssh_output=$(ssh -o PreferredAuthentications=publickey -o ConnectTimeout=5 "$alias_name" true 2>&1)
    ssh_status=$?

    if [ $ssh_status -eq 0 ]; then
        printf "${n_hdr}" "Connection succeeded."
    elif echo "$ssh_output" | grep -qi "password"; then
        printf "${a_hdr}" "Connection required a password."
        printf "${n_hdr}" "This indicates the key is not installed on the remote."
        endpoint="${ssh_user}@${ssh_host}"
        while :; do
            pk=$(query "Would you like to place the remote key now? [Y|n] ")
            pk=${pk:-y}
            if [[ $pk =~ (y|Y|n|N) ]]; then
                if [[ $pk =~ (y|Y) ]]; then
                    printf "\n${c_blue}Adding key ${pubkey_path} to ${endpoint}${c_reset}\n"

                    if command -v ssh-copy-id >/dev/null 2>&1; then
                        ssh-copy-id -i "$pubkey_path" "$endpoint"
                    else
                        printf "${c_yellow}ssh-copy-id not found, using manual append...${c_reset}\n"
                        cat "$pubkey_path" | ssh "$endpoint" '
                            mkdir -p ~/.ssh
                            chmod 700 ~/.ssh
                            cat >> ~/.ssh/authorized_keys
                            chmod 600 ~/.ssh/authorized_keys
                        '
                    fi

                    if (( rc != 0 )); then
                        printf "${c_red}❌ Failed to add key to remote host.${c_reset}\n"
                        query "Press ENTER to continue..."
                        return 1
                    fi
                    if ssh -o BatchMode=yes -o ConnectTimeout=5 ${alias_name} true; then
                        printf "${c_blue}%s\n${c_green}%s\n\e[0m" "✓ Key copied to remote host." "✓ Connection successful!"
                    else
                        printf "${a_hdr}" "Unable to connect with key. Test maually with \`ssh ${alias_name}\`"
                    fi
                fi
                break
            fi
            query-reset
        done
    else
        printf "${a_hdr}" "Connection failed: $ssh_output"
    fi

    query "Press ENTER to continue..."
}

delete-alias() {
    local config_file="$HOME/.ssh/config"

    clear
    printf "${m_hdr}" "DELETE SSH ALIAS"

    # get list of aliases ---
    mapfile -t aliases < <(awk '/^Host[[:space:]]+/ {print $2}' "$config_file" 2>/dev/null)

    if [[ ${#aliases[@]} -eq 0 ]]; then
        printf "${c_red}❌ No aliases found in %s${c_reset}\n" "$config_file"
        query "Press ENTER to continue..."
        return 1
    fi

    while :; do
        echo
        printf "${c_blue}Existing aliases:${c_reset}\n"
        for i in "${!aliases[@]}"; do
            menuitem "$((i+1))" "${aliases[$i]}"
        done
        menuitem "q" "<-Cancel / go back>"

        sel="$(query "Select an alias to delete")"
        [[ "$sel" =~ ^[Qq]$ ]] && return 0

        if [[ "$sel" =~ ^[0-9]+$ ]]; then
            idx=$((sel-1))
            if (( idx >= 0 && idx < ${#aliases[@]} )); then
                sel_alias="${aliases[$idx]}"
                break
            fi
        fi
        printf "${c_red}Invalid selection.${c_reset}\n"
        query-reset
    done

    # confirm deletion
    ans="$(query "Delete alias '$sel_alias'? [y/N]")"
    ans="${ans:-n}"
    if [[ ! "$ans" =~ ^[yY]$ ]]; then
        printf "${c_yellow}Cancelled.${c_reset}\n"
        query "Press ENTER to continue..."
        return 0
    fi

    # remove alias block
    sed -i.bak "/^Host[[:space:]]\+$sel_alias\$/,/^$/d" "$config_file"
    chmod 600 "$config_file"

    printf "${c_green}✓ Alias '%s' deleted.${c_reset}\n" "$sel_alias"
    query "Press ENTER to continue..."
}

add-key() {
    clear
    printf "${m_hdr}" "ADD KEY TO REMOTE HOST"

    local ssh_dir="$HOME/.ssh"
    local config_file="$ssh_dir/config"

    # list keys
    mapfile -t key_files < <(
        find "$ssh_dir" -maxdepth 1 -type f ! -name "*.pub" \
        -exec sh -c 'file -b "{}" | grep -qi "private key"' \; -print \
        | sed "s|$ssh_dir/||"
    )

    if [[ ${#key_files[@]} -eq 0 ]]; then
        printf "${c_red}❌ No SSH private keys found in %s${c_reset}\n" "$ssh_dir"
        query "Press ENTER to continue..."
        return 1
    fi

    while :; do
        printf "${c_blue}Available SSH private keys:${c_reset}\n"
        for i in "${!key_files[@]}"; do
            menuitem "$((i+1))" "${key_files[$i]}"
        done
        menuitem "q" "<-Cancel / go back>"

        sel="$(query "Select key to add")"
        [[ "$sel" =~ ^[Qq]$ ]] && return 0

        if [[ "$sel" =~ ^[0-9]+$ ]]; then
            idx=$((sel-1))
            if (( idx >= 0 && idx < ${#key_files[@]} )); then
                sel_key="${ssh_dir}/${key_files[$idx]}"
                pub_key="${sel_key}.pub"
                break
            fi
        fi
        printf "${c_red}Invalid selection.${c_reset}\n"
        query-reset
    done

    # check .ssh/config for alias matching this key
    rem_alias=""
    remote_user=""
    remote_host=""

    if [[ -f "$config_file" ]]; then
        rem_alias="$(awk -v key="$sel_key" '
            tolower($0) ~ "identityfile[[:space:]]+"tolower(key) {
                print prev
            }
            { prev=$2 }
        ' "$config_file")"

        if [[ -n "$rem_alias" ]]; then
            remote_host="$(awk -v alias="$rem_alias" '
                $1=="Host" && $2==alias { f=1; next }
                f && $1=="HostName" { print $2; exit }
            ' "$config_file")"

            remote_user="$(awk -v alias="$rem_alias" '
                $1=="Host" && $2==alias { f=1; next }
                f && $1=="User" { print $2; exit }
            ' "$config_file")"

            printf "${c_green}Using alias block:${c_reset}\n"
            printf "  Alias: %s\n" "$rem_alias"
            printf "  User : %s\n" "${remote_user:-<missing>}"
            printf "  Host : %s\n" "${remote_host:-<missing>}"
            printf "\n"
            query "Press ENTER to continue..."
        fi
    fi

    # ask for username and hostname/endpoint if not found in alias
    if [[ -z "$remote_host" ]]; then
        remote_host="$(query "Enter remote host (hostname or IP)")"
    fi

    if [[ -z "$remote_user" ]]; then
        remote_user="$(query "Enter remote username")"
    fi

    endpoint="$remote_user@$remote_host"

    # add the key to the remote host
    printf "\n${c_blue}Adding key ${pub_key} to ${endpoint}${c_reset}\n"

    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -i "$pub_key" "$endpoint"
        rc=$?
    else
        printf "${c_yellow}ssh-copy-id not found, using manual append...${c_reset}\n"
        cat "$pub_key" | ssh "$endpoint" '
            mkdir -p ~/.ssh
            chmod 700 ~/.ssh
            cat >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
        '
        rc=$?
    fi

    if (( rc != 0 )); then
        printf "${c_red}❌ Failed to add key to remote host.${c_reset}\n"
        query "Press ENTER to continue..."
        return 1
    fi

    printf "${c_green}✓ Key copied to remote host.${c_reset}\n"

    # test login using the key
    printf "\n${c_blue}Testing key authentication...${c_reset}\n"

    ssh -i "$sel_key" -o BatchMode=yes -o ConnectTimeout=5 "$endpoint" true
    test_rc=$?

    if (( test_rc == 0 )); then
        printf "${c_green}✓ Key authentication successful!${c_reset}\n"
    else
        printf "${c_red}❌ Authentication failed using the new key.${c_reset}\n"
        printf "${c_yellow}You may need to troubleshoot the remote authorized_keys.${c_reset}\n"
    fi

    query "Press ENTER to continue..."
}

remove-key() {
    clear
    printf "${m_hdr}" "REMOVE KEY FROM REMOTE"

    # list all public keys in .ssh/
    mapfile -t keys < <(find "$HOME/.ssh" -maxdepth 1 -type f -name "*_ed25519.pub" | sort)
    if [[ ${#keys[@]} -eq 0 ]]; then
        printf "${c_red}No public keys found in ~/.ssh/${c_reset}\n"
        query "Press ENTER to return..."
        return
    fi

    # select a key
    while :; do
        i=1
        for k in "${keys[@]}"; do
            menuitem "$i" "$(basename "$k" .pub)"
            ((i++))
        done
        menuitem "q" "Cancel and return"

        choice=$(query "Make a selection :")
        query-reset

        if [[ $choice =~ (q|Q) ]]; then
            return
        elif [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
            sel_key="${keys[$((choice-1))]}"
            key_basename=$(basename "$sel_key" .pub)
            break
        fi
    done

    # parse alias block from .ssh/config
    config_file="$HOME/.ssh/config"
    alias_name=""
    exist_user=""
    exist_host=""
    exist_key=""

    if [[ -f "$config_file" ]]; then
        sel_key_no_pub="${sel_key%.pub}"  # strip .pub

        # Find the alias whose IdentityFile matches this key
        alias_name=$(awk -v key="$sel_key_no_pub" '
            BEGIN {found=""}
            $1=="Host" {host=$2}
            $1=="IdentityFile" {
                file=$2
                gsub(/"/,"",file)
                if (file==key || file==key ".pub") {found=host; exit}
            }
            END {print found}
        ' "$config_file")

        if [[ -n "$alias_name" ]]; then
            # Extract HostName, User, IdentityFile
            exist_alias_block=$(sed -n "/^[[:space:]]*Host[[:space:]]\+$alias_name/,/^[[:space:]]*Host[[:space:]]/p" "$config_file" | sed '$d')
            exist_user=$(awk '/^[[:space:]]*User[[:space:]]+/ {print $2; exit}' <<< "$exist_alias_block")
            exist_host=$(awk '/^[[:space:]]*HostName[[:space:]]+/ {print $2; exit}' <<< "$exist_alias_block")
            exist_key=$(awk '/^[[:space:]]*IdentityFile[[:space:]]+/ {print $2; exit}' <<< "$exist_alias_block")
        fi
    fi

    # request missing info
    [[ -z "$exist_user" ]] && exist_user=$(query "Enter remote host username :")
    [[ -z "$exist_host" ]] && exist_host=$(query "Enter remote host endpoint (IP or hostname) :")
    [[ -z "$exist_key" ]] && exist_key="$sel_key"

    printf "\nAttempting to remove this key from %s:\n" "${alias_name:-<no alias>}"
    printf "  User : %s\n" "$exist_user"
    printf "  Host : %s\n" "$exist_host"
    printf "  Key  : %s\n\n" "$exist_key"
    while confirm=$(query "Please confirm you want to remove $exist_key from $alias_name, aka $exist_user@$exist_host [y|N] "); do
        confirm=${confirm:-n}
        if [[ $confirm =~ (y|Y|n|N) ]]; then
            if [[ $confirm =~ (y|Y) ]]; then
                break
            else
                return 1
            fi
            query-reset
        fi
    done

    # test connection
    printf "Testing connection...\n"
    connection_creds="$alias_name"
    if ssh -o BatchMode=yes -i "$exist_key" "$exist_user@$exist_host" "echo Connected" &>/dev/null; then
        printf "${c_green}Key successfully authenticated.${c_reset}\n"
    else
        printf "${c_red}The key cannot authenticate on the remote system.${c_reset}\n"
        printf "${c_blue}Password login will be required for key removal.${c_reset}\n"
        connection_creds="$exist_user@$exist_host"
    fi

    # remove key from remote authorized_keys
    pub_key_content=$(<"${exist_key}.pub")
    escaped_key=$(printf '%s\n' "$pub_key_content" | sed 's/[\/&]/\\&/g')

    ssh "$connection_creds" "sed -i.bak '/$escaped_key/d' ~/.ssh/authorized_keys" && \
        printf "${c_green}Key $exist_key removed from remote $alias_name, aka $exist_user@$exist_host.${c_reset}\n" || \
        printf "${c_red}Failed to remove $exist_key from $alias_name, aka $exist_user@$exist_host.${c_reset}\n"

    query "Press ENTER to continue..."
}

enable-password-login() {
    clear
    printf "${m_hdr}" "ENABLE PASSWORD LOGIN"

    local ssh_config="$HOME/.ssh/config"
    if [[ ! -f "$ssh_config" ]]; then
        printf "${c_red}No $ssh_config found. Cannot proceed.${c_reset}\n"
        query "Press ENTER to return..."
        return
    fi

    # parse all aliases from ~/.ssh/config
    mapfile -t aliases < <(awk '$1=="Host" {print $2}' "$ssh_config")
    if [[ ${#aliases[@]} -eq 0 ]]; then
        printf "${c_red}No aliases found in ~/.ssh/config.${c_reset}\n"
        query "Press ENTER to return..."
        return
    fi

    i=1
    for a in "${aliases[@]}"; do
        menuitem "$i" "$a"
        ((i++))
    done
    menuitem "q" "Cancel and return"

    while :; do
        choice=$(query "Select alias to enable password login :")
        query-reset

        if [[ $choice =~ (q|Q) ]]; then
            return
        elif [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#aliases[@]} )); then
            sel_alias="${aliases[$((choice-1))]}"
            break
        fi
    done

    # extract username and host from alias
    ssh_user=$(awk -v alias="$sel_alias" '$1=="Host" && $2==alias {f=1; next} f && $1=="User" {print $2; exit}' "$ssh_config")
    ssh_host=$(awk -v alias="$sel_alias" '$1=="Host" && $2==alias {f=1; next} f && $1=="HostName" {print $2; exit}' "$ssh_config")
    [[ -z "$ssh_user" ]] && ssh_user="root"

    printf "\nEnabling password login on %s@%s\n" "$ssh_user" "$ssh_host"
    query "Press ENTER to continue..."

    # prepare SSH command
    ssh_cmd=""
    [[ $ssh_user =~ "root" ]] && cmd_prefix="" || cmd_prefix="sudo "
    ssh_cmd+="${cmd_prefix}sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && "
    ssh_cmd+="${cmd_prefix}sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && ${cmd_prefix}systemctl restart sshd"

    # execute SSH command
    ssh "$sel_alias" "$ssh_cmd"
    if [[ $? -eq 0 ]]; then
        printf "${c_green}Password login enabled successfully on %s@%s${c_reset}\n" "$ssh_user" "$ssh_host"
    else
        printf "${c_red}Failed to enable password login on %s@%s${c_reset}\n" "$ssh_user" "$ssh_host"
    fi

    query "Press ENTER to continue..."
}

disable-password-login() {
    clear
    printf "${m_hdr}" "DISABLE PASSWORD LOGIN"

    local ssh_config="$HOME/.ssh/config"
    if [[ ! -f "$ssh_config" ]]; then
        printf "${c_red}No $ssh_config found. Cannot proceed.${c_reset}\n"
        query "Press ENTER to return..."
        return
    fi

    # parse all aliases from .ssh/config
    mapfile -t aliases < <(awk '$1=="Host" {print $2}' "$ssh_config")
    if [[ ${#aliases[@]} -eq 0 ]]; then
        printf "${c_red}No aliases found in ~/.ssh/config.${c_reset}\n"
        query "Press ENTER to return..."
        return
    fi

    i=1
    for a in "${aliases[@]}"; do
        menuitem "$i" "$a"
        ((i++))
    done
    menuitem "q" "Cancel and return"

    while :; do
        choice=$(query "Select alias to disable password login :")
        query-reset

        if [[ $choice =~ (q|Q) ]]; then
            return
        elif [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#aliases[@]} )); then
            sel_alias="${aliases[$((choice-1))]}"
            break
        fi
    done

    # extract username and host from alias
    ssh_user=$(awk -v alias="$sel_alias" '$1=="Host" && $2==alias {f=1; next} f && $1=="User" {print $2; exit}' "$ssh_config")
    ssh_host=$(awk -v alias="$sel_alias" '$1=="Host" && $2==alias {f=1; next} f && $1=="HostName" {print $2; exit}' "$ssh_config")
    [[ -z "$ssh_user" ]] && ssh_user="root"

    printf "\nDisabling password login on %s@%s\n" "$ssh_user" "$ssh_host"
    query "Press ENTER to continue..."

    # prepare SSH command
    ssh_cmd=""
    [[ $ssh_user =~ "root" ]] && cmd_prefix="" || cmd_prefix="sudo "
    ssh_cmd+="${cmd_prefix}sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && "
    ssh_cmd+="${cmd_prefix}sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && ${cmd_prefix}systemctl restart sshd"

    # execute SSH command
    ssh "$sel_alias" "$ssh_cmd"
    if [[ $? -eq 0 ]]; then
        printf "${c_green}Password login disabled successfully on %s@%s${c_reset}\n" "$ssh_user" "$ssh_host"
    else
        printf "${c_red}Failed to disable password login on %s@%s${c_reset}\n" "$ssh_user" "$ssh_host"
    fi

    query "Press ENTER to continue..."
}

query() {
    message="$@"
    printf "\e[s${c_cyan} %s ${c_reset}" "$message" >&2
    read -r answer
    printf "${answer}"
    printf "\n" >&2
}

query-reset() {
    printf "\e[u\e[K"
}

menuitem() {
    option_color=${c_cyan}
    item_color=${c_blue}
    option=$1
    item=$2
    printf "${option_color} %s) ${item_color}%s\n" "${option}" "${item}"
}

main-menu
