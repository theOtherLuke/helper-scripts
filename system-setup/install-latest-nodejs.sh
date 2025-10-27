#!/usr/bin/env bash
latest_version=$(wget -qO- https://deb.nodesource.com/ | grep -Po 'setup_\K[0-9]+(?=\.x)' | sort -nr | head -1)
bash < <(wget -qO - https://deb.nodesource.com/setup_"$latest_version".x)
apt install nodejs -y
