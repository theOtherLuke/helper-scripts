# Proxmox helper scripts

## Intel CPU affinity for big-little CPUS
 - *set-client-affinity.sh*
   
   Set cpu affinity for guest VMs and containers, restricting them to use only e-cores or p-cores, or remove restriction.
   
 - *set-host-affinity.sh*
   
   Set the Affinity for the host, restricting it to only use either p-cores or e-cores, or remove restriction.
