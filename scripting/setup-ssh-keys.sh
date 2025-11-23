#!/usr/bin/env bash
### setup-ssh-keys.sh
## Creates ssh keys and places them on a remote system. Also queries the user
## about whehter or not to disable password authentication on the remote host.

printf "\e[1;32m%s\e[0m\n" "=== SSH Key Setup Script ==="

# ─────────────────────────────────────────────────────────────────────────────
# Help Text Blocks
# ─────────────────────────────────────────────────────────────────────────────

truenas_help=$(cat <<EOF
\e[1;32m───────────────────────────────────────────────────────────────
\e[0m🐟 TrueNAS SCALE — Enable password SSH so keys can be installed
\e[1;32m───────────────────────────────────────────────────────────────
\e[0m
1. Log into TrueNAS web UI
2. Go to:  \e[1;35m**System → Services → SSH**\e[0m
3. Click **Edit** (pencil icon) and set:
      ✅ Allow Password Authentication
      ✅ Allow TCP Port Forwarding (optional)
      ✅ Add your user's group to \e[1;36m*Password Login Groups*\e[0m
4. Start the SSH service (toggle ON)
5. Enable \e[1;36m*Start Automatically*\e[0m (toggle ON)
6. Go to  \e[1;35m**Credentials → Users → (select user) → Edit**\e[0m
      ✅ Enable \e[1;36m*SSH password login enabled*\e[0m

If this script fails to place the key, add your SSH public key later at:
   \e[1;35m**Credentials → Users → (select user) → Edit**\e[0m
   Paste the contents of the <key>.pub file in \e[1;36m*Authorized Keys*\e[0m and click \e[1;36m*SAVE*\e[0m

\e[1;31mNOTE: \e[0;31mTrueNAS manages sshd_config from the UI. Avoid manually editing the file.
      This script edits the file to prove the key works. the changes will be
      overwritten at the next reboot.
\e[0m
EOF
)


proxmox_help=$(cat <<EOF
\e[1;32m──────────────────────────────────────────────────────────────
\e[0m🖥️  Proxmox VE — Enable password SSH so keys can be installed
\e[1;32m──────────────────────────────────────────────────────────────
\e[0m
On the Proxmox host (webui or console):

\e[1;34m    nano /etc/ssh/sshd_config\e[0m

Ensure these values exist or are set:
\e[1;34m
    PasswordAuthentication yes \e[0;3;36m# if setting up non-root ssh\e[0m\e[1;34m
    PubkeyAuthentication yes
    PermitRootLogin yes \e[0;3;36m# if setting up root ssh\e[0m\e[1;34m
\e[0m
Restart SSH service:

\e[1;34m    systemctl restart sshd\e[0m

EOF
)


debian_help=$(cat <<EOF
\e[1;32m──────────────────────────────────────────────────────────────
\e[0m🐧 Debian/Ubuntu — Enable password SSH so keys can be installed
\e[1;32m──────────────────────────────────────────────────────────────
\e[0m
On the remote host, edit SSH config:

\e[1;34m    sudo nano /etc/ssh/sshd_config\e[0m

Ensure these are set:
\e[1;34m
    PasswordAuthentication yes \e[0;3;36m# if setting up non-root ssh\e[0m\e[1;34m
    PubkeyAuthentication yes
    PermitRootLogin yes \e[0;3;36m# if setting up non-root ssh\e[0m\e[1;34m
\e[0m
Restart SSH:

\e[1;34m    sudo systemctl restart ssh\e[0m

EOF
)

# ─────────────────────────────────────────────────────────────────────────────
# Interactive help selection and display
# ─────────────────────────────────────────────────────────────────────────────

ask-prep-help() {
    while printf "\n\e[1;34m%s\e[0m" "Do you need help enabling password SSH on the remote host? [y/N]: " && read -rp "" -n1 answer; do
        answer="${answer:-n}"
        [[ "${answer,,}" =~ ^[yn]$ ]] && break || printf '\r\e[K'
    done
    printf '\n'
    [[ "${answer,,}" =~ [nN] ]] && return 0
    printf "\n\e[1;34m%s\e[0m\n" "Select remote host type:"
    printf "\e[1;36m%5s \e[1;35m%s\e[0m\n" "1)" "TrueNAS SCALE"
    printf "\e[1;36m%5s \e[1;35m%s\e[0m\n" "2)" "Proxmox VE"
    printf "\e[1;36m%5s \e[1;35m%s\e[0m\n" "3)" "Debian/Ubuntu"
    printf "\e[1;36m%5s \e[1;35m%s\e[0m\n" "q)" "quit help"

    while printf "\e[1;34m%s\e[0m" "Enter number: " && read -rp "" -n1 choice; do
        [[ "${choice,,}" =~ [1-3q] ]] && break || printf '\r\e[K'
    done
    printf '\n\n'
    case "$choice" in
        1) printf "$truenas_help\n" ;;
        2) printf "$proxmox_help\n" ;;
        3) printf "$debian_help\n" ;;
        q) return 0;;
    esac

    echo
    printf "\e[1;33m%s\e[0m" "Press ENTER to continue once SSH password auth is ready…" && read -rp "" _
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN SCRIPT EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

ask-prep-help

printf "✅ Continuing with key setup...\n"
sleep 1

# your key setup logic continues...

# Create directory to store local keys if missing
mkdir -p ~/.ssh

# --- Function to update ~/.ssh/config ---
update-ssh-config() {
    local alias="$1"
    local host="$2"
    local user="$3"
    local identity_file="$4"
    local update="$($5 && echo yes || echo no)"

    chmod 700 ~/.ssh

    # Avoid duplicate entries
    if grep -q "Host $alias" ~/.ssh/config 2>/dev/null; then
        printf "⚠️ SSH config already has alias %s — skipping\n" "'$alias'"
        printf "  If you want to create a new alias, rerun this script\n    and select a different alias, or delete the conflicting alias\n    and try again.\n"
        return
    fi

    cat >> ~/.ssh/config <<EOF

Host $alias
    HostName $host
    User $user
    IdentityFile $identity_file
    IdentitiesOnly yes
    # UPDATE=$update
EOF

    chmod 600 ~/.ssh/config
    printf "✅ SSH config updated with alias %s\n" "'$alias'"
}

configure-remote-host-config() {
    remote_host="$1"
    remote_user="$2"   # pass this from your parsed config

    printf "→ Preparing to update SSH security settings on %s...\n" "$remote_host" >&2

    # If user is root, ask whether to disable password login
    disable_pw_login="yes"
    if [ "$remote_user" = "root" ]; then
        printf "\nYou are connecting as ROOT on %s.\n" "$remote_host"
        while printf "\e[s\e[1;34mDisable password login for root on the remote host? [Y|n] \e[0m" && read -r ans; do
            if [[ $ans =~ (y|Y) ]]; then
                break
            elif [[ $ans =~ (n|N) ]]; then
                disable_pw_login="no"
                break
            fi
            printf "\e[u\r\e[K"
        done
        printf "→ You chose: %s password login for root.\n\n" \
            "$( [ "$disable_pw_login" = "yes" ] && echo "DISABLE" || echo "KEEP" )"
    fi

    ssh "$remote_host" bash -s <<EOF
# always ensure pubkey auth is enabled
if ! grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config; then
    printf "PubkeyAuthentication yes\n" >> /etc/ssh/sshd_config
else
    sed -i.bak -E 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
fi

# Only disable password auth if allowed
if [ "$disable_pw_login" = "yes" ]; then
    # Disable root password login
    if ! grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
        printf "PermitRootLogin prohibit-password\n" >> /etc/ssh/sshd_config
    else
        sed -i.bak -E 's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    fi

    # Disable general password auth
    if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
        printf "PasswordAuthentication no\n" >> /etc/ssh/sshd_config
    else
        sed -i.bak -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    fi
fi

# restart SSH service
if command -v configctl >/dev/null 2>&1; then
    configctl sshd restart
elif systemctl >/dev/null 2>&1; then
    systemctl reload sshd
else
    service sshd restart
fi
EOF
    return 0
}

while :; do
    while :; do
# Prompt for username
        while printf "\e[1;34m%s\e[1;36m" "Enter remote SSH username: " && read -rp "" username; do
            printf "\e[0m"
            if [[ -z "$username" ]]; then
                printf "❌ Username cannot be empty\n"
                # exit 1
            else
                break
            fi
        done

# Prompt for hostname/IP
        while printf "\e[1;34m%s\e[1;36m" "Enter remote host (IP or hostname): " && read -rp "" host; do
            printf "\e[0m"
            if [[ -z "$host" ]]; then
                printf "❌ Host cannot be empty\n"
                # exit 1
            else
                break
            fi
        done

        while printf "\e[1;34m%s\e[1;36m" "Enter an alias for the remote host: " && read -rp "" alias_name; do
            printf "\e[0m"
            if [[ -z "$alias_name" ]]; then
                printf "\e[1;31m%s\e[0m\n" "❌ Alias cannot be empty"
                # exit 1
            else
                break
            fi
        done

# Ask user whether to set the UPDATE option
        while printf "\e[1;34m%s\e[1;36m" "Set UPDATE=yes? [y|N] " && read -rp "" -n1 update; do
            printf "\e[0m"
            update="${update:-n}"
            if [[ $update =~ (y|Y|n|N) ]]; then
                case "$update" in
                    y|Y) printf '\n'; update=true; break ;;
                    n|N) printf '\n'; update=false; break ;;
                esac
            fi
            printf "\r\e[K"
        done

        endpoint="$username@$host"
        printf "\e[0;32mFull SSH endpoint:\e[0;36m %s\e[0m@\e[0;33m%s\e[0m\n" "$username" "$host"
        printf "\e[0;32mEndpoint alias :\e[0;31m %s\e[0m\n" "$alias_name"
        printf "\e[0;32mSet UPDATE=yes :\e[0;31m %s\e[0m\n" "$($update && echo yes || echo no)"
        while printf "\n\e[1;34m%s\e[0m" "Is this correct [Y|n] " && read -rp "" -n1 response; do
            response="${response:-y}"
            if [[ $response =~ (y|Y|n|N) ]]; then
                printf "\n\n"
                break
            fi
            printf "\r\e[K"
        done
        case "$response" in
            y|Y) break ;;
            n|N) continue ;;
        esac
    done

# Test reachability
    printf "→ Testing reachability to %s ...\n" "$host"
    if ! ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
        printf "❌ Host is unreachable. Check network or hostname.\n"
        #exit 1
    else
        printf "✅ Host reachable\n"
        break
    fi
done

identity_file="$HOME/.ssh/${alias_name}_ed25519"

# Ensure local .ssh directory exists
chmod 700 ~/.ssh

# Generate SSH key if missing
if [ ! -f "$identity_file" ]; then
    printf "→ No SSH key found for alias %s. Generating a new ED25519 key...\n" "$alias_name"
    ssh-keygen -t ed25519 -f "$identity_file" -N ""
    printf "✅ Key generated: %s\n" "$identity_file"
else
    printf "✅ Existing SSH key found for alias %s : %s\n" "$alias_name" "$identity_file"
fi

# Copy key to remote
printf "→ Copying public key to remote host...\n"
if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -i "${identity_file}.pub" "$endpoint"
else
    printf "⚠️  ssh-copy-id not found, using manual method...\n"
    cat "${identity_file}.pub" | ssh "$endpoint" 'mkdir -p ~/.ssh; chmod 700 ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'
fi
printf "✅ Key installed on remote host\n"

# Update SSH config with dynamically named key
update-ssh-config "$alias_name" "$host" "$username" "$identity_file" "$update"

# Test key-based login
printf "→ Testing key-based SSH login...\n"
if ssh -o PasswordAuthentication=no -o BatchMode=yes "$alias_name" true 2>/dev/null; then
    printf "✅ Passwordless SSH is working!\n"
	configure-remote-host-config "$alias_name" "$username"
else
    printf "❌ SSH key setup failed — password is still required.\n"
    printf "Check permissions on remote ~/.ssh and authorized_keys\n"
    exit 1
fi

printf "✅ All done! You can now SSH with:\n"
printf "    \e[1;36m\'ssh %s\'\e[0m\n\n" "$alias_name"
