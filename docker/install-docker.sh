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
       _            _             
    __| | ___   ___| | _____ _ __ 
   / _` |/ _ \ / __| |/ / _ \ '__|
  | (_| | (_) | (__|   <  __/ |   
   \__,_|\___/ \___|_|\_\___|_|
  _           _        _ _           
(_)_ __  ___| |_ __ _| | | ___ _ __ 
| | '_ \/ __| __/ _` | | |/ _ \ '__|
| | | | \__ \ || (_| | | |  __/ |   
|_|_| |_|___/\__\__,_|_|_|\___|_|

EOF
}
license && sleep 2
header

apt update
apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install docker-ce docker-ce-cli containerd.io docker-compose -y
systemctl enable --now docker

### install portainer
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.21.5
