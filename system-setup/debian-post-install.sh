#!/usr/bin/env bash

header() {
	clear
	cat <<"EOF"
 ____       _     _               _ ____
|  _ \  ___| |__ (_) __ _ _ __   / |___ \
| | | |/ _ \ '_ \| |/ _` | '_ \  | | __) |
| |_| |  __/ |_) | | (_| | | | | | |/ __/
|____/ \___|_.__/|_|\__,_|_| |_| |_|_____|

___  ____ ____ ___    _ _  _ ____ ___ ____ _    _
|__] |  | [__   |  __ | |\ | [__   |  |__| |    |
|    |__| ___]  |     | | \| ___]  |  |  | |___ |___
EOF
}

header

if ! whiptail --backtitle "Debian 12" --title "Post-Install" --yesno "This script will apply post-install changes to your Debian 12 system. Proceed?" 10 58; then
	exit
fi

read -p"Press [enter] to continue..." temp

header
### Correct apt sources
# remove dvd reference
echo "Removing Debian 12 dvd reference..."
sed -i 's/deb cdrom.*//' /etc/apt/sources.list

# configure repos
echo "Reconfiguring apt sources..."
repos="bookworm main non-free-firmware contrib"
sed  -i "/s/bookworm.*/$repos/g"

### Update and install additional packages
# update
echo "Updating apt and installing packages..."
apt update

# install upgrades
apt upgrade -y

# install additional packages
packages="btop neofetch cmatrix" # change to your needs
apt install $packages -y
