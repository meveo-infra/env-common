#!/bin/bash -e
  
# Install scw and 3cmd on the server
echo "Install scw and S3cmd on the machine"
apt update && apt upgrade -y
apt-get install s3cmd
sudo curl -o /usr/local/bin/scw -L "https://github.com/scaleway/scaleway-cli/releases/download/v2.4.0/scw-2.4.0-linux-x86_64"
sudo chmod +x /usr/local/bin/scw
echo y | scw init secret-key=7a8c6709-4cd2-420a-a8b8-b00c95f49668 region=fr-par with-ssh-key=false

# Configure scw on the server
scw object config get region=fr-par type=s3cmd
scw object config install region=fr-par type=s3cmd
