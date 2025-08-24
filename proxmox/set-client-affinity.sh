#!/usr/bin/env bash

p_threshold=4800 # speed threshold in mhz for determining p-core vs e-core

# Gather P-cores and E-cores safely preserving core 0
echo -e "\e[1;35mQuerying cores at threshold of 4.8GHz. You can change this threshold by modifying the 'p_threshold' variable in the script.\e[0m"
p_cores=$(lscpu -e | awk -v mhz_thr="$p_threshold" 'NR>1{
    cpu=$1; gsub(/ /,"",cpu); mhz=$7+0;
    if(mhz>=mhz_thr){
        if(p=="") p=cpu; else p=p","cpu
    }
} END{print p}')

e_cores=$(lscpu -e | awk -v mhz_thr="$p_threshold" 'NR>1{
    cpu=$1; gsub(/ /,"",cpu); mhz=$7+0;
    if(mhz>0 && mhz<mhz_thr){
        if(e=="") e=cpu; else e=e","cpu
    }
} END{print e}')

declare -A current_affinity
declare -A proposed_affinity
declare -A clients_name
declare -A clients_type

map-affinity() {
    local cores="$1"
    [ -z "$cores" ] && { echo "none"; return; }

    IFS=',' read -r -a cores_arr <<< "$cores"
    IFS=',' read -r -a p_arr <<< "$p_cores"
    IFS=',' read -r -a e_arr <<< "$e_cores"

    all_in_p=true
    all_in_e=true
    some_in_p=false
    some_in_e=false

    for c in "${cores_arr[@]}"; do
        in_p=false
        in_e=false
        [[ " ${p_arr[*]} " =~ " $c " ]] && { in_p=true; some_in_p=true; }
        [[ " ${e_arr[*]} " =~ " $c " ]] && { in_e=true; some_in_e=true; }

        $in_p || all_in_p=false
        $in_e || all_in_e=false
    done

    if $all_in_p; then
        echo "p-cores"
    elif $all_in_e; then
        echo "e-cores"
    elif $some_in_p && ! $all_in_p && ! $some_in_e; then
        echo "partial p-cores"
    elif $some_in_e && ! $all_in_e && ! $some_in_p; then
        echo "partial e-cores"
    else
        echo "mixed"
    fi
}

echo -e "\e[1;35mGathering current client affinity settings\e[0m"

# Gather LXC info
while read ctid status lock name; do
    conf=$(pct config "$ctid")
    if [[ -z $name ]]; then
        name="$lock"
    fi
    cores=$(awk -F': ' '/^lxc.cgroup2.cpuset.cpus:/ {print $2}' <<< "$conf")
    current_affinity["$ctid"]="$(map-affinity "$cores")"
    proposed_affinity["$ctid"]="$cores"
    clients_name["$ctid"]="$name"
    clients_type["$ctid"]="LXC"
done < <(pct list | tail -n +2)

# Gather VM info
while read vmid name rest; do
    conf=$(qm config "$vmid")
    cores=$(awk -F': ' '/^affinity:/ {print $2}' <<< "$conf")
    current_affinity["$vmid"]="$(map-affinity "$cores")"
    proposed_affinity["$vmid"]="$cores"
    clients_name["$vmid"]="$name"
    clients_type["$vmid"]="vm"
done < <(qm list | tail -n +2)

# Determine max name length
max_name=0
for key in "${!clients_name[@]}"; do
    len=${#clients_name[$key]}
    (( len > max_name )) && max_name=$len
done

# Main menu loop
while true; do
    menu=()
    for key in "${!current_affinity[@]}"; do
        id="$key"
        name="${clients_name[$key]}"
        current="${current_affinity[$key]}"
        proposed="${proposed_affinity[$key]}"
        display_state=$(map-affinity "$proposed")

        [ "$display_state" != "$current" ] && aff_display="*${display_state}" || aff_display="$display_state"

        padded_name="$name"
        spaces=$((max_name - ${#name} + 2))
        padded_name="${padded_name}$(printf '%*s' $spaces '')"

        menu+=("$id" "| $padded_name| $aff_display")
    done

    menu+=("SAVE" "")
    menu+=("QUIT" "")

    client=$(whiptail --title "Select client to configure" --menu "VMs/LXCs:" 25 100 15 \
        "${menu[@]}" \
        --ok-button "Select" --cancel-button "Quit" 3>&1 1>&2 2>&3)

    [ -z "$client" ] && exit
    [ "$client" == "QUIT" ] && exit
    [ "$client" == "SAVE" ] && {
        for key in "${!proposed_affinity[@]}"; do
            type="${clients_type[$key]}"
            id="$key"
            cores="${proposed_affinity[$key]}"

            if [ "$type" == "LXC" ]; then
                conf="/etc/pve/lxc/$id.conf"
                if [ -n "$cores" ]; then
                    if grep -q '^lxc.cgroup2.cpuset.cpus' "$conf"; then
                        sed -i "s/^lxc.cgroup2.cpuset.cpus.*/lxc.cgroup2.cpuset.cpus: $cores/" "$conf"
                    else
                        echo "lxc.cgroup2.cpuset.cpus: $cores" >> "$conf"
                    fi
                else
                    sed -i '/^lxc.cgroup2.cpuset.cpus/d' "$conf"
                fi
            else
                conf="/etc/pve/qemu-server/$id.conf"
                if [ -n "$cores" ]; then
                    if grep -q '^affinity:' "$conf"; then
                        sed -i "s/^affinity:.*/affinity: $cores/" "$conf"
                    else
                        echo "affinity: $cores" >> "$conf"
                    fi
                else
                    sed -i '/^affinity:/d' "$conf"
                fi
            fi
            current_affinity["$key"]="$(map-affinity "$cores")"
        done
        whiptail --msgbox "All proposed changes saved to config files!" 8 60
        continue
    }

    [ -z "$client" ] && continue

    # Secondary menu
    current_aff="${current_affinity[$client]}"
    proposed_aff="${proposed_affinity[$client]}"

    current_state=$(map-affinity "$current_aff")
    proposed_state=$(map-affinity "$proposed_aff")

    desc_text="Current: $current_state"
    [[ "$current_state" == "mixed" ]] && desc_text+="\n$current_aff"
    # Show proposed if different
    [[ "$proposed_state" != "$current_state" ]] && desc_text+="\nProposed: $proposed_state"

    # Show actual cores if mixed or partial
    if [[ "$proposed_state" == "mixed" || "$proposed_state" == "partial p-cores" || "$proposed_state" == "partial e-cores" ]]; then
        desc_text+="\nCores: $proposed_aff"
    fi

    choice=$(whiptail --title "Select affinity for $client" --menu "$desc_text" 18 70 7 \
        "1" "p-cores" \
        "2" "e-cores" \
        "3" "none" \
        "4" "ADVANCED" \
        "5" "Go back" 3>&1 1>&2 2>&3)

    case $choice in
        1) proposed_affinity["$client"]="$p_cores" ;;
        2) proposed_affinity["$client"]="$e_cores" ;;
        3) proposed_affinity["$client"]="" ;;
        4)
            checklist=()
            IFS=',' read -r -a p_arr <<< "$p_cores"
            IFS=',' read -r -a e_arr <<< "$e_cores"
            IFS=',' read -r -a current_arr <<< "${proposed_affinity[$client]}"

            for c in ${p_arr[@]}; do
                state="OFF"
                [[ " ${current_arr[*]} " =~ " $c " ]] && state="ON"
                checklist+=("$c" "p-core" "$state")
            done
            for c in ${e_arr[@]}; do
                state="OFF"
                [[ " ${current_arr[*]} " =~ " $c " ]] && state="ON"
                checklist+=("$c" "e-core" "$state")
            done

            selected=$(whiptail --title "Advanced core selection for $client" --checklist "Select cores:" 25 60 18 \
                "${checklist[@]}" 3>&1 1>&2 2>&3)

            selected=$(echo "$selected" | sed 's/"//g' | tr ' ' ',')
            proposed_affinity["$client"]="$selected"
            ;;
    esac
done
