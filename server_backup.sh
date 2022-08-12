#!/bin/bash -e

expired_image=$(date +'%d%b%Y' --date='1 day ago')
instance_name=$(hostname)
instance_id=$(scw instance server list | grep $instance_name > /tmp/volume_backup.txt ; awk '{print $1}' /tmp/volume_backup.txt)
image_id=$(scw instance image list| grep $expired_image > /tmp/server_image.txt ; awk '{print $1}' /tmp/server_image.txt)
expired_snapshot=$(scw instance snapshot list| grep ${expired_image}_snap_0 > /tmp/expired_snapshot.txt ; awk '{print $1}' /tmp/expired_snapshot.txt)
scw instance snapshot delete $expired_snapshot
scw instance image delete $image_id
scw instance server backup $instance_id name=`date +%d%b%Y`
