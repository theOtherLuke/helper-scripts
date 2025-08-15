#!/usr/bin/env bash

# Limits the host systemd processes to P-cores, E-cores, or all cores

p_threshold=4800 # speed threshold in mhz for determining p-core vs e-core
p_cores=$(lscpu -e | awk -v mhz_thr="$p_threshold" 'NR>1{cpu=$1; gsub(/ /,"",cpu); mhz=$7+0; if(mhz>=mhz_thr){p=p? p" "cpu : cpu}} END{print p}')
e_cores=$(lscpu -e | awk -v mhz_thr="$p_threshold" 'NR>1{cpu=$1; gsub(/ /,"",cpu); mhz=$7+0; if(mhz>0 && mhz<mhz_thr){e=e? e" "cpu : cpu}} END{print e}')

choice=$(whiptail --title "Host CPU Affinity" \
    --menu "Select cores for host processes:" 15 60 4 \
    "1" "P-cores" \
    "2" "E-cores" \
    "3" "All cores" 3>&1 1>&2 2>&3)

exit_code=$?
[ $exit_code -ne 0 ] && exit 0

case $choice in
    1) cores="$p_cores"
       core_set="P-cores" ;;
    2) cores="$e_cores"
       core_set="E-cores" ;;
    3) cores="" ;;
    *) exit 1 ;;
esac

conf_file="/etc/systemd/system.conf"

cp "$conf_file" "${conf_file}.bak.$(date +%Y%m%d%H%M%S)"

sed -i '/^CPUAffinity=/d' "$conf_file"

if [ -n "$cores" ]; then
    echo "CPUAffinity=$cores" >> "$conf_file"
    echo "Host CPU affinity set to: $core_set"
else
    echo "Host can now use all cores"
fi

echo "Reloading systemd manager configuration..."
systemctl daemon-reexec

echo "Done. Some processes may require a reboot to fully respect the new affinity."
