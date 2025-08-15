#!/usr/bin/env bash

p_threshold=4800 # speed threshold in mhz for determining p-core vs e-core
p_cores=$(lscpu -e | awk -v mhz_thr="$p_threshold" 'NR>1{cpu=$1; gsub(/ /,"",cpu); mhz=$7+0; if(mhz>=mhz_thr){p=p? p" "cpu : cpu}} END{print p}')
e_cores=$(lscpu -e | awk -v mhz_thr="$p_threshold" 'NR>1{cpu=$1; gsub(/ /,"",cpu); mhz=$7+0; if(mhz>0 && mhz<mhz_thr){e=e? e" "cpu : cpu}} END{print e}')

declare -A current_affinity
declare -A proposed_affinity
declare -A clients_name
declare -A clients_type

map_affinity() {
    local cores="$1"
    [ -z "$cores" ] && { echo "none"; return; }

    IFS=',' read -r -a cores_arr <<< "$cores"
    IFS=',' read -r -a p_arr <<< "$p_cores"
    IFS=',' read -r -a e_arr <<< "$e_cores"

    all_in_p=true
    all_in_e=true
    mixed=false

    for c in "${cores_arr[@]}"; do
        in_p=false
        in_e=false
        [[ " ${p_arr[*]} " =~ " $c " ]] && in_p=true
        [[ " ${e_arr[*]} " =~ " $c " ]] && in_e=true

        $in_p || all_in_p=false
        $in_e || all_in_e=false
    done

    if $all_in_p; then
        echo "p-cores"
    elif $all_in_e; then
        echo "e-cores"
    elif ! $all_in_p && ! $all_in_e; then
        echo "mixed"
    else
        echo "none"
    fi
}

while read ctid rest; do
    name=$(pct config "$ctid" | awk -F': ' '/^hostname:/ {print $2}')
    conf="/etc/pve/lxc/$ctid.conf"
    if grep -q '^lxc.cgroup2.cpuset.cpus=' "$conf"; then
        cores=$(grep '^lxc.cgroup2.cpuset.cpus=' "$conf" | cut -d= -f2)
    else
        cores=""
    fi
    aff=$(map_affinity "$cores")
    current_affinity["lxc_$ctid"]="$aff"
    proposed_affinity["lxc_$ctid"]="$aff"
    clients_name["lxc_$ctid"]="$name"
    clients_type["lxc_$ctid"]="LXC"
done < <(pct list | tail -n +2 | awk '{print $1}')

while read vmid name rest; do
    conf="/etc/pve/qemu-server/$vmid.conf"
    if grep -q '^affinity:' "$conf"; then
        cores=$(grep '^affinity:' "$conf" | awk -F': ' '{print $2}')
    else
        cores=""
    fi
    aff=$(map_affinity "$cores")
    current_affinity["vm_$vmid"]="$aff"
    proposed_affinity["vm_$vmid"]="$aff"
    clients_name["vm_$vmid"]="$name"
    clients_type["vm_$vmid"]="vm"
done < <(qm list | tail -n +2)

max_name=0
for key in "${!clients_name[@]}"; do
    LEN=${#clients_name[$key]}
    (( LEN > max_name )) && max_name=$LEN
done

while true; do
    menu=()
    for key in "${!current_affinity[@]}"; do
        id="${key#*_}"
        name="${clients_name[$key]}"
        current="${current_affinity[$key]}"
        proposed="${proposed_affinity[$key]}"

        [ "$proposed" != "$current" ] && aff_display="*${proposed}" || aff_display="$current"

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
            id="${key#*_}"
            selected="${proposed_affinity[$key]}"

            if [ "$selected" == "p-cores" ]; then
                cores="$p_cores"
            elif [ "$selected" == "e-cores" ]; then
                cores="$e_cores"
            else
                cores=""
            fi
            cores_qm=${cores// /,}
            if [ "$type" == "LXC" ]; then
                conf="/etc/pve/lxc/$id.conf"
                if [ -n "$cores" ]; then
                    if grep -q '^lxc.cgroup2.cpuset.cpus' "$conf"; then
                        sed -i "s/^lxc.cgroup2.cpuset.cpus=.*/lxc.cgroup2.cpuset.cpus=$cores_qm/" "$conf"
                    else
                        echo "lxc.cgroup2.cpuset.cpus=$cores_qm" >> "$conf"
                    fi
                else
                    sed -i '/^lxc.cgroup2.cpuset.cpus/d' "$conf"
                fi
            else
                conf="/etc/pve/qemu-server/$id.conf"
                if [ -n "$cores" ]; then
                    if grep -q '^affinity:' "$conf"; then
                        sed -i "s/^affinity:.*/affinity: $cores_qm/" "$conf"
                    else
                        echo "affinity: $cores_qm" >> "$conf"
                    fi
                else
                    sed -i '/^affinity:/d' "$conf"
                fi
            fi
            current_affinity["$key"]="${proposed_affinity[$key]}"
        done
        whiptail --msgbox "All proposed changes saved to config files!" 8 60
        continue
    }

    key=""
    for k in "${!current_affinity[@]}"; do
        if [ "${k#*_}" == "$client" ]; then
            key="$k"
            break
        fi
    done
    [ -z "$key" ] && continue

    choice=$(whiptail --title "Select affinity for $client" --menu "Choose core assignment:" 15 60 4 \
        "1" "p-cores" \
        "2" "e-cores" \
        "3" "none" \
        "4" "Go back" 3>&1 1>&2 2>&3)

    case $choice in
        1) proposed_affinity["$key"]="p-cores" ;;
        2) proposed_affinity["$key"]="e-cores" ;;
        3) proposed_affinity["$key"]="none" ;;
    esac
done
