#!/usr/bin/env bash
license(){
	echo -e "\e[1;32m"
	cat <<EOF
MIT License

Copyright (c) 2024 nodaddyno

Permission is hereby granted, free of charge, to any person obtaining a
     copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
                      the following conditions:

The above copyright notice and this permission notice shall be included
        in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
      OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
       SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
EOF
	echo -e "\e[0m"
}
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
license && sleep 2
header

if ! whiptail --backtitle "Debian 12" --title "Post-Install" --yesno "This script will apply post-install changes to your Debian 12 system. Proceed?" 10 58; then
	exit
fi

header
### Correct apt sources
# remove dvd reference
echo "Disabling Debian 12 dvd reference..."
sed -i 's/deb cdrom/#deb cdrom/' /etc/apt/sources.list

# configure repos
echo "Reconfiguring apt sources..."
repos="main non-free-firmware contrib"
sed  -i -r "s/bookworm .*/bookworm $repos/g" /etc/apt/sources.list
sed  -i -r "s/bookworm-updates .*/bookworm-updates $repos/g" /etc/apt/sources.list
sed  -i -r "s/bookworm-security .*/bookworm-security $repos/g" /etc/apt/sources.list

### Update and install additional packages
# update
echo "Updating apt and installing packages..."
apt update

# install upgrades
apt upgrade -y

# install additional packages
packages="btop htop neofetch cmatrix sudo" # change to your needs
apt install $packages -y

# configure tabs for nano
cat << 'EOF' > ~/.nanorc
set tabsize 4
set tabstospaces
EOF
